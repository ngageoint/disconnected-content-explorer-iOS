//
//  ReportManager.m
//  InteractiveReports
//

#import "LocalReportManager.h"

@interface LocalReportManager () {
    dispatch_queue_t backgroundQueue;
    NSMutableArray *reports;
    NSFileManager *fileManager;
    NSURL *documentsDirectory;
}

@end


@implementation LocalReportManager
- (id)init
{
    self = [super init];
    
    if (self) {
        reports = [[NSMutableArray alloc] init];
        fileManager = [NSFileManager defaultManager];
        backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        NSArray *dirUrls = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        documentsDirectory = dirUrls[0];
    }
    
    return self;
}


- (NSMutableArray *)getReports
{
    return reports;
}


/* 
 * Load the report zips and PDFs that are stored in the app's Documents directory
 */
- (void)loadReports
{
    NSArray *extensions = [NSArray arrayWithObjects:@"zip", @"pdf", @"doc", @"docx", @"ppt", @"pptx", @"xls", @"xlsx", nil];
    
    NSDirectoryEnumerator *files = [fileManager enumeratorAtURL:documentsDirectory
        includingPropertiesForKeys:@[NSURLNameKey, NSURLIsRegularFileKey, NSURLIsReadableKey, NSURLLocalizedNameKey]
        options:(NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsSubdirectoryDescendants)
        errorHandler:nil];
    
    reports = [[NSMutableArray alloc] init];
    
    int i = 0;
    for (NSURL *file in files) {
        NSLog(@"enmerating file %@", file);
        NSNumber* isRegularFile;
        [file getResourceValue:&isRegularFile forKey: NSURLIsRegularFileKey error: nil];
        if (isRegularFile.boolValue && [extensions containsObject:file.pathExtension]) {
            Report *placeholderReport = [Report reportWithTitle:file.lastPathComponent];
            [reports addObject:placeholderReport];
            
            NSString *reportName = placeholderReport.title;
            NSString *fileExtension = file.pathExtension;
            
            if ( [fileExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame )
            {
                dispatch_async(backgroundQueue, ^(void) {
                    [self processZip:reportName atFilePath:file atIndex:i];
                });
            } else { // PDFs and office files
                dispatch_async(backgroundQueue, ^(void) {
                    Report *report = [Report reportWithTitle:reportName];
                    report.url = file;
                    report.reportID = reportName;
                    report.fileExtension = fileExtension;
                    report.isEnabled = YES;
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEReportUpdatedNotification"
                                                                        object:report
                                                                      userInfo:@{
                                                                                 @"index": [NSString stringWithFormat:@"%d", i],
                                                                                 @"report": report}];
                });
            }
            i++;
        }
    }
}


- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler
{
    [self loadReports];
    completionHandler();
}


/* 
 * Unzip the report, if there is a metadata.json file included, spruce up the object so it displays fancier
 * in the list, grid, and map views. Otherwise, note the error and send back an error placeholder object.
 */
- (void)processZip:(NSString*)reportName atFilePath:(NSURL *)filePath atIndex:(int)index
{
    Report *report;
    
    @try {
        NSRange rangeOfDot = [reportName rangeOfString:@"."];
        NSString *fileExtension = [reportName pathExtension];
        NSString *unzipDirName = (rangeOfDot.location != NSNotFound) ? [reportName substringToIndex:rangeOfDot.location] : nil;
        NSURL *unzipDir = [documentsDirectory URLByAppendingPathComponent: unzipDirName];
        NSURL *jsonFile = [unzipDir URLByAppendingPathComponent: @"metadata.json"];
        NSError *error = nil;
        
        if(![fileManager fileExistsAtPath:unzipDir.path]) {
            @try {
                [self unzipFileAtPath:filePath withIndex:index toDirectory:documentsDirectory error:&error];
            } @catch (ZipException *ze) {
                report = [Report reportWithTitle:reportName];
                report.description = @"Unable to open report";
                report.isEnabled = NO;
            }
        }
        
        // Handle the metadata.json, make the report fancier, if it is available
        if ( [fileManager fileExistsAtPath:jsonFile.path] && error == nil) {
            NSString *jsonString = [[NSString alloc] initWithContentsOfFile:jsonFile.path encoding:NSUTF8StringEncoding error:NULL];
            NSError *error;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
            
            report = [Report reportWithTitle: [json objectForKey:@"title"]];
            report.description = [json objectForKey:@"description"];
            report.thumbnail = [json objectForKey:@"thumbnail"];
            report.tileThumbnail = [json objectForKey:@"tile_thumbnail"];
            report.lat = [[json valueForKey:@"lat"] doubleValue];
            report.lon = [[json valueForKey:@"lon"] doubleValue];
            report.reportID = [json valueForKey:@"reportID"];
            report.fileExtension = fileExtension;
            report.url = unzipDir;
            report.isEnabled = YES;
        } else if (error == nil) {
            report = [Report reportWithTitle:unzipDirName];
            report.url = unzipDir;
            report.isEnabled = YES;
        }
    }
    @catch (NSException *exception) {
        report = [Report reportWithTitle:reportName];
        report.description = @"Unable to open report";
        report.isEnabled = NO;
    }
    @finally {
        // Send a message to let the views know that the report list has needs to be updated
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEReportUpdatedNotification"
                                                            object:report
                                                          userInfo:@{@"index": [NSString stringWithFormat:@"%d", index], @"report": report}];
    }
}


- (BOOL)unzipFileAtPath:(NSURL *)filePath withIndex:(int)index toDirectory:(NSURL *)directory error:(NSError **)error {
    if (error) {
        *error = nil;
    }
    
    ZipFile *unzipFile = [[ZipFile alloc] initWithFileName:filePath.path mode:ZipFileModeUnzip];
    int totalNumberOfFiles = (int)[unzipFile numFilesInZip];
    [unzipFile goToFirstFileInZip];
    for (int i = 0; i < totalNumberOfFiles; i++) {
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
        
        [unzipFile goToNextFileInZip];
        if (i % 25 == 0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEReportUnzipProgressNotification"
                                                                object:nil
                                                              userInfo:@{@"index": [NSString stringWithFormat:@"%d", index],
                                                                      @"progress": [NSString stringWithFormat:@"%d", i],
                                                            @"totalNumberOfFiles": [NSString stringWithFormat:@"%d", totalNumberOfFiles]}];
        }
    }

    [unzipFile close];
    return YES;
}

@end
