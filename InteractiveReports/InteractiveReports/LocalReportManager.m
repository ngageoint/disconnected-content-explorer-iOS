//
//  ReportManager.m
//  InteractiveReports
//

#import "LocalReportManager.h"

@interface LocalReportManager () {
    dispatch_queue_t backgroundQueue;
    NSMutableArray *reports;
    NSFileManager *fileManager;
    NSString *documentsDirectory;
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
        documentsDirectory = [NSHomeDirectory() stringByAppendingString:@"/Documents/"];
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
    NSArray *fileList = [fileManager contentsOfDirectoryAtPath:documentsDirectory error: nil];
    NSArray *reportTitles = [fileList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension IN %@", extensions]];
    
    reports = [[NSMutableArray alloc] init];
    
    if (reportTitles != nil) {
        for (int i = 0; i < reportTitles.count; i++) {
            // create a placeholder that will get overwritten once the report is unpackaged
            Report *placeholderReport = [Report reportWithTitle:[reportTitles objectAtIndex:i]];
            [reports addObject:placeholderReport];
            
            NSString *reportName = [reportTitles objectAtIndex:i];
            NSString *fileExtension = [reportName pathExtension];
            NSString *filePath = [NSString stringWithFormat:@"%@/%@", documentsDirectory, reportName];
            
            if ( [fileExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame )
            {
                dispatch_async(backgroundQueue, ^(void){
                    [self processZip:reportName atFilePath:filePath atIndex:i];
                });
            } else { // PDFs and office files
                dispatch_async(backgroundQueue, ^(void){
                    Report *report = [Report reportWithTitle:reportName];
                    report.url = [NSURL URLWithString:documentsDirectory];
                    report.reportID = reportName;
                    report.fileExtension = fileExtension;
                    report.isEnabled = YES;
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEReportUpdatedNotification"
                                                                        object:report
                                                                      userInfo:@{@"index": [NSString stringWithFormat:@"%d", i], @"report": report}];
                });
            }
        }
    }
}


/* 
 * Unzip the report, if there is a metadata.json file included, spruce up the object so it displays fancier
 * in the list, grid, and map views. Otherwise, note the error and send back an error placeholder object.
 */
- (void)processZip:(NSString*)reportName atFilePath:(NSString *)filePath atIndex:(int)index
{
    Report *report;
    
    @try {
        NSRange rangeOfDot = [reportName rangeOfString:@"."];
        NSString *fileExtension = [reportName pathExtension];
        NSString *unzippedFolder = (rangeOfDot.location != NSNotFound) ? [reportName substringToIndex:rangeOfDot.location] : nil;
        NSString *jsonFilePath = [NSString stringWithFormat:@"%@/%@/%@", documentsDirectory, unzippedFolder, @"metadata.json"];
        NSError *error = nil;
        
        if(![fileManager fileExistsAtPath:[NSString stringWithFormat:@"%@/%@", documentsDirectory, unzippedFolder]])
        {
            @try {
                [self unzipFileAtPath:filePath withIndex:index toDirectory:documentsDirectory error:&error];
            } @catch (ZipException *ze) {
                report = [Report reportWithTitle:reportName];
                report.description = @"Unable to open report";
                report.isEnabled = NO;
            }
        }
        
        // Handle the metadata.json, make the report fancier, if it is available
        if ( [fileManager fileExistsAtPath:jsonFilePath] && error == nil)
        {
            NSString *jsonString = [[NSString alloc] initWithContentsOfFile:jsonFilePath encoding:NSUTF8StringEncoding error:NULL];
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
            report.url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/", documentsDirectory, unzippedFolder]];
            report.isEnabled = YES;
        } else if (error == nil) {
            report = [Report reportWithTitle:unzippedFolder];
            report.url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/", documentsDirectory, unzippedFolder]];
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


- (BOOL)unzipFileAtPath:(NSString *)filePath withIndex:(int)index toDirectory:(NSString *)directory error:(NSError **)error {
    if (error) {
        *error = nil;
    }
    
    ZipFile *unzipFile = [[ZipFile alloc] initWithFileName:filePath mode:ZipFileModeUnzip];
    int totalNumberOfFiles = (int)[unzipFile numFilesInZip];
    [unzipFile goToFirstFileInZip];
    for (int i = 0; i < totalNumberOfFiles; i++) {
        FileInZipInfo *info = [unzipFile getCurrentFileInZipInfo];
        NSString *name = info.name;
        if (![name hasSuffix:@"/"]) {
            NSString *filePath = [directory stringByAppendingPathComponent:name];
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
