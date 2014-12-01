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

@interface ReportAPI () {
    dispatch_queue_t backgroundQueue;
    NSMutableArray *reports;
    NSFileManager *fileManager;
    NSURL *documentsDirectory;
}

@end


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
        documentsDirectory = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
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
    [reports removeAllObjects];
    
    NSArray *extensions = [NSArray arrayWithObjects:@"zip", @"pdf", @"doc", @"docx", @"ppt", @"pptx", @"xls", @"xlsx", nil];
    
    NSDirectoryEnumerator *files = [fileManager enumeratorAtURL:documentsDirectory
                                     includingPropertiesForKeys:@[NSURLNameKey, NSURLIsRegularFileKey, NSURLIsReadableKey, NSURLLocalizedNameKey]
                                                        options:(NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsSubdirectoryDescendants)
                                                   errorHandler:nil];
    int i = 0;
    
    for (NSURL *file in files) {
        NSNumber* isRegularFile;
        [file getResourceValue:&isRegularFile forKey: NSURLIsRegularFileKey error: nil];
        if (isRegularFile.boolValue && [extensions containsObject:file.pathExtension]) {
            Report *report = [Report reportWithTitle:file.lastPathComponent];
            [reports addObject:report];
            
            NSString *reportName = report.title;
            NSString *fileExtension = file.pathExtension;
            
            if ( [fileExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame ) {
                dispatch_async(backgroundQueue, ^(void) {
                    [self processZip:report atFilePath:file atIndex:i];
                });
            }
            else { // PDFs and office files
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


- (void)importReportFromUrl:(NSURL *)reportUrl afterImport:(void(^)(void))afterImportBlock
{
    NSURL *documentsDir = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *fileName = reportUrl.lastPathComponent;
    NSURL *destFile = [documentsDir URLByAppendingPathComponent:fileName];
    NSError *error;
    
    [fileManager moveItemAtURL:reportUrl toURL:destFile error:&error];
    
    if (error) {
        NSLog(@"error moving file %@ to documents directory for open request: %@", reportUrl, [error localizedDescription]);
    }
    
    NSMutableDictionary *urlParameters = [NSMutableDictionary dictionary];
    [urlParameters setObject:fileName forKey:@"reportID"];
    
    [self loadReportsWithCompletionHandler:^{
        // TODO: ensure these notifications are on the main thread
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEReportsRefreshed"
                                                            object:nil
                                                          userInfo:nil];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEURLOpened"
                                                            object:nil
                                                          userInfo:urlParameters];
    }];
}


/*
 * Unzip the report, if there is a metadata.json file included, spruce up the object so it displays fancier
 * in the list, grid, and map views. Otherwise, note the error and send back an error placeholder object.
 */
- (void)processZip:(Report*)report atFilePath:(NSURL *)sourceFile atIndex:(int)index
{
    NSString *sourceFileName = sourceFile.lastPathComponent;
    report.title = sourceFile.lastPathComponent;
    @try {
        NSRange rangeOfDot = [sourceFileName rangeOfString:@"."];
        NSString *fileExtension = [sourceFile pathExtension];
        NSString *unzipDirName = (rangeOfDot.location != NSNotFound) ? [sourceFileName substringToIndex:rangeOfDot.location] : nil;
        NSURL *unzipDir = [documentsDirectory URLByAppendingPathComponent: unzipDirName];
        NSURL *jsonFile = [unzipDir URLByAppendingPathComponent: @"metadata.json"];
        NSError *error = nil;
        
        if(![fileManager fileExistsAtPath:unzipDir.path]) {
            [self unzipFileAtPath:sourceFile toDirectory:documentsDirectory error:&error];
        }
        
        // Handle the metadata.json, make the report fancier, if it is available
        if ( [fileManager fileExistsAtPath:jsonFile.path] && error == nil) {
            NSString *jsonString = [[NSString alloc] initWithContentsOfFile:jsonFile.path encoding:NSUTF8StringEncoding error:NULL];
            NSError *error;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
            
            report.title = [json objectForKey:@"title"];
            report.description = [json objectForKey:@"description"];
            report.thumbnail = [json objectForKey:@"thumbnail"];
            report.tileThumbnail = [json objectForKey:@"tile_thumbnail"];
            report.lat = [[json valueForKey:@"lat"] doubleValue];
            report.lon = [[json valueForKey:@"lon"] doubleValue];
            report.reportID = [json valueForKey:@"reportID"];
            report.fileExtension = fileExtension;
            report.url = unzipDir;
            report.isEnabled = YES;
        }
        else if (error == nil) {
            report.title = unzipDirName;
            report.url = unzipDir;
            report.isEnabled = YES;
        }
    }
    @catch (NSException *exception) {
        report.title = sourceFileName;
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


- (BOOL)unzipFileAtPath:(NSURL *)filePath toDirectory:(NSURL *)directory error:(NSError **)error {
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
            [[NSNotificationCenter defaultCenter]
             postNotificationName:@"DICEReportUnzipProgressNotification" object:nil
             userInfo:@{
                        @"progress": [NSString stringWithFormat:@"%d", i],
                        @"totalNumberOfFiles": [NSString stringWithFormat:@"%d", totalNumberOfFiles]}];
        }
    }
    
    [unzipFile close];
    return YES;
}

@end
