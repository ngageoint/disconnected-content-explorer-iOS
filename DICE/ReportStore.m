//
//  ReportStore.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import "ReportStore.h"
#import "InspectReportArchiveOperation.h"
#import "MatchReportTypeToContentAtPathOperation.h"
#import "DICEOZZipFileArchive.h"


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


// TODO: thread safety for reports array
@implementation ReportStore
{
    NSURL *_reportsDir;
    NSFileManager *_fileManager;
    DICEUtiExpert *_utiExpert;
    NSOperationQueue *_importQueue;
    NSMutableArray<Report *> *_reports;
    NSMutableDictionary<NSURL *, ImportProcess *> *_pendingImports;
}

+ (instancetype)sharedInstance
{
    // TODO: initialize singleton with actual dependency injection; then how to get the instance into view controllers?
    static ReportStore *_sharedInstance = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedInstance = [[ReportStore alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init
{
    NSURL *docsDir = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    return [self initWithReportsDir:docsDir
        fileManager:[NSFileManager defaultManager]
        utiExpert:[[DICEUtiExpert alloc] init]
        importQueue:[[NSOperationQueue alloc] init]];
}

- (instancetype)initWithReportsDir:(NSURL *)reportsDir fileManager:(NSFileManager *)fileManager utiExpert:(DICEUtiExpert *)utiExpert importQueue:(NSOperationQueue *)importQueue
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _reports = [NSMutableArray array];
    _reportsDir = reportsDir;
    _fileManager = fileManager;
    _utiExpert = utiExpert;
    _importQueue = importQueue;
    _pendingImports = [NSMutableDictionary dictionary];

    return self;
}


- (NSArray<Report *> *)loadReports
{
    NSArray *files = [_fileManager contentsOfDirectoryAtURL:_reportsDir includingPropertiesForKeys:nil options:0 error:nil];

    // TODO: remove deleted reports from list
    // TODO: establish reserved/exclude paths in docs dir

    for (NSURL *file in files) {
        NSLog(@"attempting to add report from file %@", file);
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

    // TODO: restore or replace with different view to indicate empty list and link to fetch examples
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
    // TODO: add excluded path checking, e.g., for geopackage folder
    Report *report = [self reportAtPath:reportUrl];

    if (report) {
        return report;
    }

    CFStringRef reportUti = [_utiExpert preferredUtiForExtension:reportUrl.pathExtension conformingToUti:NULL];
    report = [[Report alloc] initWithTitle:reportUrl.path];
    report.isEnabled = NO;
    report.url = reportUrl;
    report.uti = reportUti;
    report.reportID = reportUrl.path;
    report.title = reportUrl.lastPathComponent;
    report.summary = @"Importing...";

    // TODO: report is added here but might not be imported;
    // maybe update report to reflect status then let nature take its course and remove on the next refresh
    [_reports addObject:report];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportAdded] object:self userInfo:@{@"report": report}];
    });

    if ([_utiExpert uti:reportUti conformsToUti:kUTTypeZipArchive]) {
        // get zip file listing on background thread
        // find appropriate report type for archive contents
        id<DICEArchive> archive = [[DICEOZZipFileArchive alloc] initWithArchivePath:reportUrl utType:reportUti];
        InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:self.reportTypes utiExpert:_utiExpert];
        [_importQueue addOperation:op];
        return report;
    }
    else {
        MatchReportTypeToContentAtPathOperation *op = nil;
    }

    id<ReportType> reportType = [self reportTypeForFile:reportUrl];

    if (!reportType) {
        // TODO: consider adding placeholder report for file to notify user the report is not supported
        return nil;
    }

    ImportProcess *import = [reportType createProcessToImportReport:report toDir:_reportsDir];
    import.delegate = self;

    [_importQueue addOperations:import.steps waitUntilFinished:NO];

    return report;
}

- (Report *)reportForID:(NSString *)reportID
{
    return [self.reports filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"reportID == %@", reportID]].firstObject;
}

#pragma mark - ImportDelegate methods

- (void)reportWasUpdatedByImportProcess:(ImportProcess *)import
{
    // TODO: dispatch notifications
}

- (void)importDidFinishForImportProcess:(ImportProcess *)import
{
    @synchronized (_pendingImports) {
        NSSet<NSURL *> *keys = [_pendingImports keysOfEntriesPassingTest:^BOOL(NSURL * _Nonnull key, ImportProcess * _Nonnull obj, BOOL * _Nonnull stop) {
            return obj == import;
        }];
        [_pendingImports removeObjectsForKeys:keys.allObjects];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        import.report.isEnabled = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportImportFinished] object:self userInfo:@{@"report": import.report}];
    });
}

#pragma mark - private_methods

- (id<ReportType>)reportTypeForFile:(NSURL *)reportPath
{
    for (id<ReportType> maybe in self.reportTypes) {
        if ([maybe couldImportFromPath:reportPath]) {
            return maybe;
        }
    }
    return nil;
}

- (nullable Report *)reportAtPath:(NSURL *)path
{
    // TODO: this seems superfluous because the report would be in the reports array already anyway; maybe remove _pendingImports
    ImportProcess *import;
    @synchronized (_pendingImports) {
        import = _pendingImports[path];
    }
    if (import) {
        return import.report;
    }

    for (Report *candidate in self.reports) {
        if ([candidate.url isEqual:path]) {
            return candidate;
        }
    }
    return nil;
}

@end
