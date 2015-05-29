//
//  ReportStore.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "ReportStore.h"

#import "Report.h"
#import "ReportType.h"
#import "ReportAPI.h"

@implementation ReportStore
{
    NSMutableArray *_reports;
    NSFileManager *_fileManager;
    NSURL *_documentsDir;
}

- (instancetype)init
{
    self = [super init];
    if (!self)
    {
        return nil;
    }

    _reports = [NSMutableArray array];
    _fileManager = [NSFileManager defaultManager];
    _documentsDir = [_fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];

    return self;
}


- (NSArray *)getReports
{
    return [NSArray arrayWithArray:(NSArray *)_reports];
}


- (NSArray *)loadReports
{
    [_reports filterUsingPredicate:[NSPredicate predicateWithBlock: ^BOOL (Report *report,
        NSDictionary *bindings) {
            return (!report.isEnabled && [_fileManager fileExistsAtPath:report.url.path]) ||
            (report.isEnabled && [_fileManager fileExistsAtPath:report.url.path]);
            // TODO: dispatch report removed notification?
        }]];

    NSDirectoryEnumerator *files = [_fileManager enumeratorAtURL:_documentsDir
        includingPropertiesForKeys:@[
            NSURLNameKey,
            NSURLIsRegularFileKey,
            NSURLIsDirectoryKey,
            NSURLIsReadableKey,
            NSURLLocalizedNameKey
        ]
        options:(NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsSubdirectoryDescendants)
        errorHandler:nil];

    for (NSURL *file in files)
    {
        NSLog(@"ReportAPI: attempting to add report from file %@", file);
        /*
         * While seemingly unnecessary, this bit of code avoids an error that arises
         * because the NSURL objects returned by the above enumerator have a /private
         * component prepended to them which ends up resulting in null CGPDFDocument
         * objects in the vfrReader code and app crashing.  For some reason, this
         * only happens when the PDF file name has spaces.  This code effectively
         * removes the /private component from the report URL, because the
         * documentsDir NSURL object does not end up getting the /private prefix.
         */
        NSString *fileName = [file.lastPathComponent stringByRemovingPercentEncoding];
        NSURL *reportUrl = [_documentsDir URLByAppendingPathComponent:fileName];
        [self attemptToImportReportFromResource:reportUrl];
    }

    if (_reports.count == 0)
    {
//        [reports addObject:[self getUserGuideReport]];
    }
    else {

    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
        postNotificationName:[ReportNotification reportsLoaded]
        object:self
        userInfo:nil];
    });

    return [self getReports];
}

- (Report *)attemptToImportReportFromResource:(NSURL *)reportUrl
{
    id<ReportType> reportType = [self reportTypeForFile:reportUrl.path];
    if (!reportType) {
        return nil;
    }
    Report *report = [[Report alloc] initWithTitle:reportUrl.path];
    report.url = reportUrl;
    [_reports addObject:report];
    [reportType importReport:report];
    return report;
}

#pragma mark - private_methods

- (id<ReportType>)reportTypeForFile:(NSString *)reportPath
{
    __block id<ReportType> reportType = nil;
    [self.reportTypes enumerateObjectsUsingBlock:^(id<ReportType> maybe, NSUInteger idx, BOOL *stop) {
        if ([maybe couldHandleFile:reportPath]) {
            reportType = maybe;
            *stop = YES;
        }
    }];
    return reportType;
}

@end
