//
//  ReportAPI.m
//  InteractiveReports
//

#import "ReportAPI.h"
#import "zlib.h"
#import "ZipFile.h"
#import "ZipReadStream.h"
#import "ZipException.h"
#import "FileInZipInfo.h"


@implementation ReportNotification

+ (NSString *)reportAdded {
    return @"DICE.ReportAdded";
}
+ (NSString *)reportUpdated {
    return @"DICE.ReportUpdated";
}
+ (NSString *)reportsLoaded {
    return @"DICE.ReportsLoaded";
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

@end


@interface ReportAPI () {
    dispatch_queue_t backgroundQueue;
    NSMutableArray *reports;
    NSFileManager *fileManager;
    NSURL *documentsDir;
    // TODO: move this to ResourceTypes and consolidate all report type ingestion and handling
    // right now DICENavigationController, AppDelegate, and this class all have logic for
    // report type handling
    NSArray *recognizedFileExtensions;
}

@end

// TODO: implement report content hashing to detect new reports and duplicates

@implementation ReportAPI

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
    
    if (self) {
        reports = [[NSMutableArray alloc] init];
        fileManager = [NSFileManager defaultManager];
        backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        documentsDir = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        recognizedFileExtensions = @[@"zip", @"pdf", @"doc", @"docx", @"ppt", @"pptx", @"xls", @"xlsx", @"kml"];
    }
    
    return self;
}


- (NSMutableArray *)getReports
{
    return reports;
}


- (Report *)reportForID:(NSString *)reportID
{
    return [reports filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"reportID == %@", reportID]].firstObject;
}


/*
 * Load the report zips and PDFs that are stored in the app's Documents directory
 */
- (void)loadReports
{
    [reports removeAllObjects];

    NSDirectoryEnumerator *files = [fileManager enumeratorAtURL:documentsDir
        includingPropertiesForKeys:@[NSURLNameKey, NSURLIsRegularFileKey, NSURLIsReadableKey, NSURLLocalizedNameKey]
        options:(NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsSubdirectoryDescendants)
        errorHandler:nil];
    
    for (NSURL *file in files) {
        [self addReportFromFile:file afterComplete:nil];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportsLoaded] object:self userInfo:nil];
}


- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler
{
    [self loadReports];
    completionHandler();
}


- (void)importReportFromUrl:(NSURL *)reportURL afterImport:(void(^)(Report *))afterImportBlock
{
    // TODO: notify import begin if anyone cares
    
    NSString *fileName = reportURL.lastPathComponent;
    NSURL *destFile = [documentsDir URLByAppendingPathComponent:fileName];
    NSError *error;
    
    [fileManager moveItemAtURL:reportURL toURL:destFile error:&error];
    
    if (error) {
        NSLog(@"error moving file %@ to documents directory for open request: %@", reportURL, [error localizedDescription]);
    }

    [self addReportFromFile:destFile afterComplete:afterImportBlock];
}


- (void)addReportFromFile:(NSURL *)file afterComplete:(void(^)(Report *))afterCompleteBlock
{
    NSNumber* isRegularFile;
    [file getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
    
    if (isRegularFile.boolValue && [recognizedFileExtensions containsObject:file.pathExtension]) {
        NSString *title = [file.lastPathComponent stringByDeletingPathExtension];
        Report *report = [Report reportWithTitle:title];
        report.sourceFile = file;
        report.reportID = [report.sourceFile.lastPathComponent stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        [reports addObject:report];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportAdded]
                                                            object:self
                                                          userInfo:@{
                                                              @"report": report,
                                                              @"index": [NSString stringWithFormat:@"%lu", reports.count - 1]
                                                          }];
        
        NSString *fileExtension = file.pathExtension;
        
        if ( [fileExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame ) {
            dispatch_async(backgroundQueue, ^(void) {
                [self processZip:report atIndex:(reports.count - 1)];
                if (afterCompleteBlock) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        afterCompleteBlock(report);
                    });
                }
            });
        }
        else { // PDFs and office files
            dispatch_async(backgroundQueue, ^(void) {
                report.reportID = report.sourceFile.lastPathComponent;
                // make sure the url's baseURL property is set
                report.url = [NSURL URLWithString:report.sourceFile.lastPathComponent relativeToURL:[file URLByDeletingLastPathComponent]];
                report.fileExtension = fileExtension;
                report.isEnabled = YES;
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:[ReportNotification reportUpdated]
                    object:self
                    userInfo:@{
                        @"index": [NSString stringWithFormat:@"%lu", reports.count - 1],
                        @"report": report
                    }];
                if (afterCompleteBlock) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        afterCompleteBlock(report);
                    });
                }
            });
        }
    }
}


/*
 * Unzip the report, if there is a metadata.json file included, spruce up the object so it displays fancier
 * in the list, grid, and map views. Otherwise, note the error and send back an error placeholder object.
 */
- (void)processZip:(Report*)report atIndex:(NSUInteger)index
{
    NSURL *sourceFile = report.sourceFile;
    NSString *sourceFileName = sourceFile.lastPathComponent;
    report.title = sourceFile.lastPathComponent;
    @try {
        NSRange rangeOfDot = [sourceFileName rangeOfString:@"."];
        NSString *fileExtension = [sourceFile pathExtension];
        NSString *expectedContentDirName = (rangeOfDot.location != NSNotFound) ? [sourceFileName substringToIndex:rangeOfDot.location] : nil;
        NSURL *expectedContentDir = [documentsDir URLByAppendingPathComponent: expectedContentDirName isDirectory:YES];
        NSURL *jsonFile = [expectedContentDir URLByAppendingPathComponent: @"metadata.json"];
        NSError *error;
        
        if (![fileManager fileExistsAtPath:expectedContentDir.path]) {
            [self unzipReportContents:report toDirectory:documentsDir error:&error];
        }
        
        
        // Handle the metadata.json, make the report fancier, if it is available
        if ( [fileManager fileExistsAtPath:jsonFile.path] && error == nil) {
            NSString *jsonString = [[NSString alloc] initWithContentsOfFile:jsonFile.path encoding:NSUTF8StringEncoding error:NULL];
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];

            NSString *reportID = [json valueForKey:@"reportID"];
            if (reportID) {
                report.reportID = reportID;
            }
            report.title = [json objectForKey:@"title"];
            report.description = [json objectForKey:@"description"];
            report.thumbnail = [json objectForKey:@"thumbnail"];
            report.tileThumbnail = [json objectForKey:@"tile_thumbnail"];
            report.lat = [[json valueForKey:@"lat"] doubleValue];
            report.lon = [[json valueForKey:@"lon"] doubleValue];
            report.fileExtension = fileExtension;
            report.isEnabled = YES;
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
    }
    @catch (NSException *exception) {
        report.title = sourceFileName;
        report.description = @"Unable to open report";
        report.isEnabled = NO;
    }
    @finally {
        // Send a message to let the views know that the report list needs to be updated
        [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportUpdated]
             object:self
             userInfo:@{
                 @"index": [NSString stringWithFormat:@"%lu", index],
                 @"report": report
             }];
    }
}


- (BOOL)unzipReportContents:(Report *)report toDirectory:(NSURL *)directory error:(NSError **)error {
    if (error) {
        *error = nil;
    }
    
    ZipFile *unzipFile = [[ZipFile alloc] initWithFileName:report.sourceFile.path mode:ZipFileModeUnzip];
    int totalNumberOfFiles = (int)[unzipFile numFilesInZip];
    [unzipFile goToFirstFileInZip];
    for (int filesExtracted = 0; filesExtracted < totalNumberOfFiles; filesExtracted++) {
        FileInZipInfo *info = [unzipFile getCurrentFileInZipInfo];
        NSString *name = info.name;
        if (![name hasSuffix:@"/"]) {
            NSString *filePath = [directory.path stringByAppendingPathComponent:name];
            NSString *basePath = [filePath stringByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:error]) {
                [unzipFile close];
                return NO;
            }
            
            [[NSData data] writeToFile:filePath options:0 error:nil];
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
            ZipReadStream *read = [unzipFile readCurrentFileInZip];
            NSUInteger count;
            NSMutableData *data = [NSMutableData dataWithLength:2048];
            while ((count = [read readDataWithBuffer:data])) {
                data.length = count;
                [handle writeData:data];
                data.length = 2048;
            }
            [read finishedReading];
            [handle closeFile];
        }
        
        report.progress = filesExtracted;
        [unzipFile goToNextFileInZip];
        
        if (filesExtracted % 25 == 0) {
            [[NSNotificationCenter defaultCenter]
                postNotificationName:[ReportNotification reportImportProgress]
                object:self
                userInfo:@{
                    @"report": report,
                    @"progress": [NSString stringWithFormat:@"%d", filesExtracted],
                    @"totalNumberOfFiles": [NSString stringWithFormat:@"%d", totalNumberOfFiles]
                }];
        }
    }
    
    [unzipFile close];
    return YES;
}

@end
