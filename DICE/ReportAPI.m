//
//  ReportAPI.m
//  InteractiveReports
//

#import "ReportAPI.h"

#import "ResourceTypes.h"
#import "zlib.h"
#import "ZipFile.h"
#import "ZipReadStream.h"
#import "ZipException.h"
#import "FileInZipInfo.h"
#import "GPKGIOUtils.h"
#import "DICEConstants.h"
#import "AFNetworking.h"
#import <math.h>

@implementation ReportNotification

+ (NSString *)reportAdded {
    return @"DICE.ReportAdded";
}
+ (NSString *)reportImportBegan {
    return @"DICE.ReportImportBegan";
}
+ (NSString *)reportImportProgress {
    return @"DICE.ReportImportProgress";
}
+ (NSString *)reportImportFinished {
    return @"DICE.ReportImportFinished";
}
+ (NSString *)reportImportFail {
    return @"DICE.ReportImportFail";
}
+ (NSString *)reportsLoaded {
    return @"DICE.ReportsLoaded";
}

@end



// TODO: implement report content hashing to detect new reports and duplicates
// TODO: assess thread safety of reports array read/write and notifications - dispatch everything on main thread?
/*
     i think currently everything that reads the array is on the main thread, but we should address thread safety properly
 */
// TODO: use core data to build report store?

@implementation ReportAPI
{
    dispatch_queue_t reportListQueue;
    dispatch_queue_t backgroundQueue;
    NSMutableArray *reports;
    NSFileManager *fileManager;
    NSURL *documentsDir;
}

+ (NSString *)userGuideReportID {
    return @"DICE.UserGuideReport";
}

+ (ReportAPI *)sharedInstance
{
    static ReportAPI *_sharedInstance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedInstance = [[ReportAPI alloc] init];
    });
    return _sharedInstance;
}

- (id)init
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    reports = [[NSMutableArray alloc] init];
    fileManager = [NSFileManager defaultManager];
    reportListQueue = dispatch_queue_create("dice.report_list", DISPATCH_QUEUE_SERIAL);
    backgroundQueue = dispatch_queue_create("dice_work", DISPATCH_QUEUE_CONCURRENT);
    documentsDir = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    
    return self;
}

- (void)dealloc
{
    dispatch_release(reportListQueue);
    dispatch_release(backgroundQueue);
}

- (NSArray *)getReports
{
    return reports;
}

- (Report *)reportForID:(NSString *)reportID
{
    return [reports filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"reportID == %@", reportID]].firstObject;
}

- (Report *)reportForSourceFile:(NSURL *)sourceFile
{
    return [reports filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Report *report, NSDictionary *bindings) {
        return [report.sourceFile.absoluteString isEqualToString:sourceFile.absoluteString];
    }]].firstObject;
}

/*
 * Load the reports that are stored in the app's Documents directory
 */
- (void)loadReports
{
    NSLog(@"ReportAPI: loading reports from %@ ...", documentsDir);
    
    dispatch_async(reportListQueue, ^{
        [reports filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(Report *report, NSDictionary *bindings) {
            return (!report.isEnabled && [fileManager fileExistsAtPath:report.sourceFile.path])
            || (report.isEnabled && [fileManager fileExistsAtPath:report.url.path]);
            // TODO: dispatch report removed notification
        }]];
        
        NSDirectoryEnumerator *files = [fileManager enumeratorAtURL:documentsDir
            includingPropertiesForKeys:@[NSURLNameKey, NSURLIsRegularFileKey, NSURLIsReadableKey, NSURLLocalizedNameKey]
            options:(NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsSubdirectoryDescendants)
            errorHandler:nil];
        
        for (NSURL *file in files) {
            /*
             While seemingly unnecessary, this bit of code avoids an error that arises because the NSURL objects
             returned by the above enumerator have a /private component prepended to them which ends up resulting
             in null CGPDFDocument objects in the vfrReader code and app crashing.  For some reason, this only 
             happens when the PDF file name has spaces.  This code effectively removes the /private component
             from the report URL, because the documentsDir NSURL object does not end up getting the /private
             prefix.
             */
            NSString *fileName = [file.lastPathComponent stringByRemovingPercentEncoding];
            if(![fileName isEqualToString:[GPKGIOUtils geoPackageDirectory]]){
                NSLog(@"ReportAPI: attempting to add report from file %@", file);
                NSURL *reportURL = [documentsDir URLByAppendingPathComponent:fileName isDirectory:NO];
                [self addReportFromFile:reportURL afterComplete:nil];
            }
        }
        
        if (reports.count == 0) {
            [reports addObject:[self getUserGuideReport]];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportsLoaded] object:self userInfo:nil];
        });
    });
}


- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler
{
    [self loadReports];
    completionHandler();
}


- (void)importReportFromUrl:(NSURL *)reportURL afterImport:(void(^)(Report *))afterImportBlock
{
    NSLog(@"ReportAPI: importing report from %@", reportURL);
    // TODO: notify import begin if anyone cares
    
    NSString *fileName = reportURL.lastPathComponent;
    NSURL *destFile = [documentsDir URLByAppendingPathComponent:fileName];
    NSError *error;
    
    [fileManager moveItemAtURL:reportURL toURL:destFile error:&error];
    
    if (error) {
        NSLog(@"ReportAPI: error moving file %@ to documents directory for import request: %@", reportURL, [error localizedDescription]);
    }

    dispatch_async(reportListQueue, ^{
        [self addReportFromFile:destFile afterComplete:afterImportBlock];
    });
}

// TODO: remove afterCompleteBlock and use only the notification?
- (void)addReportFromFile:(NSURL *)file afterComplete:(void(^)(Report *))afterCompleteBlock
{
    NSLog(@"ReportAPI: attempting to create report from %@", file);
    NSNumber* isRegularFile;
    [file getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
    
    if (isRegularFile.boolValue && [ResourceTypes canOpenResource:file]) {
        Report *report = [self reportForSourceFile:file];
        if (report) {
            // it's already in the list, and possibly still unzipping
            // TODO: check if the source file is new and re-import the file
            return;
        }
        
        NSString *title = [file.lastPathComponent stringByDeletingPathExtension];
        report = [[Report alloc] initWithTitle:title];
        report.sourceFile = file;
        report.reportID = [report.sourceFile.lastPathComponent stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        [reports addObject:report];
        NSLog(@"ReportAPI: added new report placeholder at index %lu for report %@", reports.count - 1, file);
        Report *placeHolder = [self reportForID:[ReportAPI userGuideReportID]];
        if (placeHolder) {
            // TODO: notify report removed
            [reports removeObject:placeHolder];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
                postNotificationName:[ReportNotification reportAdded] object:self
                userInfo:@{
                    @"report": report,
                    @"index": [NSString stringWithFormat:@"%lu", reports.count - 1]
                }];
        });
        
        NSString *fileExtension = file.pathExtension;
        
        if ( [fileExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame ) {
            dispatch_async(backgroundQueue, ^(void) {
                [self processZip:report atIndex:(reports.count - 1)];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (afterCompleteBlock) {
                        afterCompleteBlock(report);
                    }
                    [self notifyReportImportFinished:report];
                });
            });
        }
        else { // PDFs and office files
            dispatch_async(backgroundQueue, ^(void) {
                // make sure the url's baseURL property is set
                NSURL *baseURL = [report.sourceFile URLByDeletingLastPathComponent];
                NSString *reportFileName = [report.sourceFile.lastPathComponent stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
                report.url = [NSURL URLWithString:reportFileName relativeToURL:baseURL];
                report.fileExtension = fileExtension;
                report.isEnabled = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (afterCompleteBlock) {
                        afterCompleteBlock(report);
                    }
                    [self notifyReportImportFinished:report];
                });
                
            });
        }
    }
}


- (void)notifyReportImportFinished:(Report *)report
{
    [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportImportFinished] object:self
        userInfo:@{
            @"report": report,
            @"index": [NSString stringWithFormat:@"%lu", [reports indexOfObject:report]]
        }];
}


/*
 * Unzip the report, if there is a metadata.json file included, spruce up the object so it displays fancier
 * in the list, grid, and map views. Otherwise, note the error and send back an error placeholder object.
 */
- (void)processZip:(Report*)report atIndex:(NSUInteger)index
{
    NSLog(@"processing zipped report %@ ...", report.sourceFile);
    NSURL *sourceFile = report.sourceFile;
    NSString *sourceFileName = sourceFile.lastPathComponent;
    report.title = sourceFile.lastPathComponent;

    NSRange rangeOfDot = [sourceFileName rangeOfString:@"."];
    NSString *fileExtension = [sourceFile pathExtension];
    NSString *expectedContentDirName = (rangeOfDot.location != NSNotFound) ? [sourceFileName substringToIndex:rangeOfDot.location] : nil;
    NSURL *expectedContentDir = [documentsDir URLByAppendingPathComponent: expectedContentDirName isDirectory:YES];
    NSURL *jsonFile = [expectedContentDir URLByAppendingPathComponent: @"metadata.json"];
    NSError *error;
    
    if (![fileManager fileExistsAtPath:expectedContentDir.path]) {
        [self unzipReportContents:report toDirectory:documentsDir error:&error];
    }
    else {
        NSLog(@"directory already exists for report zip %@", report.sourceFile);
    }
    
    // Handle the metadata.json, make the report fancier, if it is available
    if ( [fileManager fileExistsAtPath:jsonFile.path] && error == nil) {
        NSString *jsonString = [[NSString alloc] initWithContentsOfFile:jsonFile.path encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];

        // TODO: what are the potential problems of changing the report id here from its initial value above?
        NSString *reportID = [json valueForKey:@"reportID"];
        if (reportID) {
            report.reportID = reportID;
        }
        report.title = [json objectForKey:@"title"];
        report.summary = [json objectForKey:@"description"];
        report.thumbnail = [json objectForKey:@"thumbnail"];

        if ([json objectForKey:@"tile_thumbnail"] != nil) {
            report.tileThumbnail = [json objectForKey:@"tile_thumbnail"];
        } else if (report.thumbnail != nil)  {
            report.tileThumbnail = report.thumbnail;
        }
        
        report.lat = [[json valueForKey:@"lat"] doubleValue];
        report.lon = [[json valueForKey:@"lon"] doubleValue];
        report.fileExtension = fileExtension;
        report.isEnabled = YES;
        
        // Set the map to zoom to all report locations
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:DICE_ZOOM_TO_REPORTS];
        [defaults synchronize];
    }
    else if (error == nil) {
        report.title = expectedContentDirName;
        report.isEnabled = YES;
    }
    
    if (!report.reportID) {
        report.reportID = report.sourceFile.lastPathComponent;
    }
    
    // make sure url's baseURL property is set
    report.url = [NSURL URLWithString:@"index.html" relativeToURL:expectedContentDir];
    
    NSLog(@"finished processing report zip %@; report url: %@", report.sourceFile, report.url.absoluteString);
}


- (BOOL)unzipReportContents:(Report *)report toDirectory:(NSURL *)directory error:(NSError **)error {
    if (error) {
        *error = nil;
    }
    
    NSLog(@"ReportAPI: extracting report contents from %@", report.sourceFile);
    
    @try {
        ZipFile *unzipFile = [[ZipFile alloc] initWithFileName:report.sourceFile.path mode:ZipFileModeUnzip];
        int totalNumberOfFiles = (int)[unzipFile numFilesInZip];
        report.totalNumberOfFiles = totalNumberOfFiles;
        [unzipFile goToFirstFileInZip];
        NSUInteger bufferSize = 1 << 20;
        NSMutableData *entryData = [NSMutableData dataWithLength:(bufferSize)];
        for (int filesExtracted = 0; filesExtracted < totalNumberOfFiles; filesExtracted++) {
            FileInZipInfo *info = [unzipFile getCurrentFileInZipInfo];
            NSString *name = info.name;
            if (![name hasSuffix:@"/"]) {
                NSString *filePath = [directory.path stringByAppendingPathComponent:name];
                NSString *basePath = [filePath stringByDeletingLastPathComponent];
                if (![fileManager fileExistsAtPath:basePath]) {
                    if (![fileManager createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:error]) {
                        [unzipFile close];
                        return NO;
                    }
                }
                
                [[NSData data] writeToFile:filePath options:0 error:nil];
                NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
                ZipReadStream *read = [unzipFile readCurrentFileInZip];
                NSUInteger count;
                while ((count = [read readDataWithBuffer:entryData])) {
                    entryData.length = count;
                    [handle writeData:entryData];
                    entryData.length = bufferSize;
                }
                [read finishedReading];
                [handle closeFile];
            }
            
            report.progress = filesExtracted;
            [unzipFile goToNextFileInZip];
            
            if (filesExtracted % 25 == 0) {
                report.progress = filesExtracted;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter]
                     postNotificationName:[ReportNotification reportImportProgress]
                     object:self
                     userInfo:@{
                                @"report": report,
                                @"progress": [NSString stringWithFormat:@"%d", filesExtracted],
                                @"totalNumberOfFiles": [NSString stringWithFormat:@"%d", totalNumberOfFiles]
                                }];
                });
            }
        }
        
        [unzipFile close];
        
        NSLog(@"ReportAPI: finished extracting report %@", report.sourceFile);
        
        return YES;

    }
    @catch(ZipException *exctption) {
        NSLog(@"Problem unzipping %@: %@",report.title, exctption.description);
        
        [[NSNotificationCenter defaultCenter]
         postNotificationName:[ReportNotification reportImportFail] object:self
         userInfo:@{
                    @"report": report,
                    @"index": [NSString stringWithFormat:@"%lu", reports.count - 1],
                    @"message": exctption.description
                    }];

        return NO;
    }
}


- (Report*)getUserGuideReport
{
    Report *userGuide = [[Report alloc] init];
    userGuide.title = @"Tap here to download the user guide";
    userGuide.summary = @"Select \"Open in DICE\"";
    userGuide.isEnabled = YES;
    userGuide.reportID = [ReportAPI userGuideReportID];
    
    return userGuide;
}


- (void)downloadReportAtURL:(NSURL *)URL {
    // make a new report object that can track the download progress
    Report *report = [[Report alloc] initWithTitle:[URL absoluteString]];
    report.isEnabled = NO;
    report.summary = @"Downloading...";
    [reports addObject:report];
    
    // broadcast a message with that report
    NSString *filename = [URL lastPathComponent];
    NSURL *destFile = [documentsDir URLByAppendingPathComponent:filename];
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    AFHTTPRequestOperation *downloadRequest = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    downloadRequest.outputStream = [NSOutputStream outputStreamToFileAtPath:[destFile path] append:NO];
    
    [downloadRequest setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"Successfully downloaded: %@", [URL absoluteString]);
        // Maybe add a dictionary value to NSUserDefaults to a downloaded dictionary with the URL as a key and YES as the value, check that dictionary before displaying the action sheet
        [self loadReports];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Problem downloading %@: %@", [URL path], [error localizedDescription]);
    }];
    
    // update download progress
    [downloadRequest setDownloadProgressBlock:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
        // TODO: Add code
        // set the description to a status using the size of the file and download progress
        float progress = ((float)totalBytesRead) / totalBytesExpectedToRead;
        
        if (fmodf(totalBytesRead, 25) == 0) {
            report.summary = [NSString stringWithFormat:@"%lld of %lld downloaded", totalBytesRead, totalBytesExpectedToRead];
            report.downloadSize = totalBytesExpectedToRead;
            report.downloadProgress = totalBytesRead;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:[ReportNotification reportImportProgress]
                 object:self
                 userInfo:@{
                            @"report": report,
                            @"progress": [NSString stringWithFormat:@"%g", progress],
                            @"totalNumberOfFiles": [NSString stringWithFormat:@"%lld downloaded", totalBytesExpectedToRead]
                            }];
            });

        }
        
    }];
    
    [downloadRequest start];
    
    // hand off completed file to be unzipped
}


@end
