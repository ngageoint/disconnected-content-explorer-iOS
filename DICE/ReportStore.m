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
    NSMutableArray<Report *> *_reports;
    NSFileManager *_fileManager;
    NSURL *_reportsDir;
    NSOperationQueue *_importQueue;
    NSMutableDictionary<NSURL *, id<ImportProcess>> *_pendingImports;
}

- (instancetype)init
{
    NSURL *docsDir = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    return [self initWithReportsDir:docsDir fileManager:[NSFileManager defaultManager]];
}

- (instancetype)initWithReportsDir:(NSURL *)reportsDir fileManager:(NSFileManager *)fileManager
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _reports = [NSMutableArray array];
    _reportsDir = reportsDir;
    _fileManager = fileManager;
    _importQueue = [[NSOperationQueue alloc] init];
    _pendingImports = [NSMutableDictionary dictionary];

    return self;
}


- (NSArray<Report *> *)loadReports
{
    [_reports filterUsingPredicate:[NSPredicate predicateWithBlock:
        ^BOOL (Report *report, NSDictionary *bindings) {
            BOOL importing = [_pendingImports objectForKey:report.url] != nil;
            return importing;
            // TODO: dispatch report removed notification?
        }]];

    NSArray *files = [_fileManager contentsOfDirectoryAtURL:_reportsDir includingPropertiesForKeys:nil options:0 error:nil];

    for (NSURL *file in files) {
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
        NSURL *reportUrl = [_reportsDir URLByAppendingPathComponent:fileName];

        [self attemptToImportReportFromResource:reportUrl];
    }

    // TODO: tests for user guide report
//    if (_reports.count == 0)
//    {
//        [reports addObject:[self getUserGuideReport]];
//    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
        postNotificationName:[ReportNotification reportsLoaded]
        object:self
        userInfo:nil];
    });

    return self.reports;
}

- (Report *)attemptToImportReportFromResource:(NSURL *)reportUrl
{
    id<ImportProcess> import = [_pendingImports objectForKey:reportUrl];

    if (import) {
        return import.report;
    }

    id<ReportType> reportType = [self reportTypeForFile:reportUrl];

    if (!reportType) {
        // TODO: consider adding placeholder report for file to notify user the report is not supported
        return nil;
    }

    Report *report = [[Report alloc] initWithTitle:reportUrl.path];
    report.isEnabled = NO;
    report.url = reportUrl;
    report.reportID = reportUrl.path;
    report.title = reportUrl.lastPathComponent;
    report.summary = @"Importing...";

    [_reports addObject:report];

    [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportAdded] object:self userInfo:@{@"report": report}];

    import = [reportType createProcessToImportReport:report toDir:_reportsDir];
    import.delegate = self;
    [_pendingImports setObject:import forKey:reportUrl];

    // TODO: track pending imports by report object and/or add self as import delegate
    NSOperation *step;
    while ((step = [import nextStep]) != nil) {
        [_importQueue addOperation:step];
    }

    return report;
}

#pragma mark - ImportDelegate methods

- (void)reportWasUpdatedByImportProcess:(id<ImportProcess>)import
{
    // TODO: dispatch notifications
}

- (void)importDidFinishForImportProcess:(id<ImportProcess>)import
{
    NSSet<NSURL *> *keys = [_pendingImports keysOfEntriesPassingTest:^BOOL(NSURL * _Nonnull key, id<ImportProcess>  _Nonnull obj, BOOL * _Nonnull stop) {
        return obj == import;
    }];
    [_pendingImports removeObjectsForKeys:[keys allObjects]];
}

#pragma mark - private_methods

- (id<ReportType>)reportTypeForFile:(NSURL *)reportPath
{
    for (id<ReportType> maybe in self.reportTypes) {
        if ([maybe couldHandleFile:reportPath]) {
            return maybe;
        }
    }
    return nil;
}

- (Report *)reportForPath:(NSURL *)path
{
    for (Report *candidate in self.reports) {
        if ([candidate.url isEqual:path]) {
            return candidate;
        }
    }
    return nil;
}

@end
