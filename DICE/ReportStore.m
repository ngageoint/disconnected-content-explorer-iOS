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
#import "ImportProcess+Internal.h"
#import "UnzipOperation.h"
#import "DICEDefaultArchiveFactory.h"
#import "DICEArchive.h"
#import "Report.h"
#import "ReportType.h"
#import "DICEUtiExpert.h"


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
    id<DICEArchiveFactory> _archiveFactory;
    NSOperationQueue *_importQueue;
    NSMutableArray<Report *> *_reports;
    NSMutableDictionary<NSURL *, Report *> *_pendingImports;
    void *ARCHIVE_MATCH_CONTEXT;
    void *CONTENT_MATCH_CONTEXT;
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
    DICEUtiExpert *utiExpert = [[DICEUtiExpert alloc] init];
    return [self initWithReportsDir:docsDir
        fileManager:[NSFileManager defaultManager]
        archiveFactory:[[DICEDefaultArchiveFactory alloc] initWithUtiExpert:utiExpert]
        utiExpert:utiExpert
        importQueue:[[NSOperationQueue alloc] init]];
}

- (instancetype)initWithReportsDir:(NSURL *)reportsDir fileManager:(NSFileManager *)fileManager archiveFactory:(id<DICEArchiveFactory>)archiveFactory utiExpert:(DICEUtiExpert *)utiExpert importQueue:(NSOperationQueue *)importQueue
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _reports = [NSMutableArray array];
    _reportsDir = reportsDir;
    _fileManager = fileManager;
    _archiveFactory = archiveFactory;
    _utiExpert = utiExpert;
    _importQueue = importQueue;
    _pendingImports = [NSMutableDictionary dictionary];
    ARCHIVE_MATCH_CONTEXT = &ARCHIVE_MATCH_CONTEXT;
    CONTENT_MATCH_CONTEXT = &CONTENT_MATCH_CONTEXT;

    return self;
}


- (NSArray *)loadReports
{
    // TODO: ensure this does not get called more than twice concurrently - main thread only
    // TODO: remove deleted reports from list
    // TODO: establish reserved/exclude paths in docs dir

    NSIndexSet *defunctReports = [_reports indexesOfObjectsPassingTest:^BOOL(Report *report, NSUInteger idx, BOOL *stop) {
        if ([_fileManager fileExistsAtPath:report.url.path]) {
            return NO;
        }
        if (_pendingImports[report.url] != nil) {
            return NO;
        }
        if ([_pendingImports.allValues containsObject:report]) {
            return NO;
        }
        return YES;
    }];
    if (defunctReports.count > 0) {
        [_reports removeObjectsAtIndexes:defunctReports];
        // TODO: dispatch reports changed notification, or just wait till load is complete
    }

    NSArray *files = [_fileManager contentsOfDirectoryAtURL:_reportsDir includingPropertiesForKeys:nil options:0 error:nil];
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

        // TODO: suspend notifications while loading reports
        [self attemptToImportReportFromResource:reportUrl];
    }

    // TODO: restore or replace with different view to indicate empty list and link to fetch examples
    // TODO: tests for user guide report
//    if (_reports.count == 0)
//    {
//        [reports addObject:[self getUserGuideReport]];
//    }

    // TODO: probably not necessary
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
    // TODO: run on background thread to avoid synchronization around report list and pending imports
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
    report.title = reportUrl.lastPathComponent;
    report.summary = @"Importing...";

    // TODO: report is added here but might not be imported;
    // maybe update report to reflect status but leave in list so user can choose to delete it
    [_reports addObject:report];
    _pendingImports[reportUrl] = report;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportAdded] object:self userInfo:@{@"report": report}];
    });

    if ([_utiExpert uti:reportUti conformsToUti:kUTTypeZipArchive]) {
        // get zip file listing on background thread
        // find appropriate report type for archive contents
        id<DICEArchive> archive = [_archiveFactory createArchiveForResource:reportUrl withUti:reportUti];
        InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:self.reportTypes utiExpert:_utiExpert];
        [op addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:nil context:ARCHIVE_MATCH_CONTEXT];
        [_importQueue addOperation:op];
        return report;
    }
    else {
        MatchReportTypeToContentAtPathOperation *op =
            [[MatchReportTypeToContentAtPathOperation alloc] initWithReport:report candidateTypes:self.reportTypes];
        [op addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:nil context:CONTENT_MATCH_CONTEXT];
        [_importQueue addOperation:op];
    }

    return report;
}

- (Report *)reportForID:(NSString *)reportID
{
    return [self.reports filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"reportID == %@", reportID]].firstObject;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)context
{
    // extract archive or get matched report type
    if (context == CONTENT_MATCH_CONTEXT) {
        MatchReportTypeToContentAtPathOperation *op = object;
        [op removeObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) context:CONTENT_MATCH_CONTEXT];
        id<ReportType> type = op.matchedReportType;
        if (type) {
            [_importQueue addOperationWithBlock:^{
                ImportProcess *process = [type createProcessToImportReport:op.report toDir:_reportsDir];
                process.delegate = self;
                [_importQueue addOperations:process.steps waitUntilFinished:NO];
            }];
        }
        else {
            op.report.error = @"Unkown content type";
        }
    }
    else if (context == ARCHIVE_MATCH_CONTEXT) {
        // TODO: extract the zip and stuff
        InspectReportArchiveOperation *op = object;
        [op removeObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) context:ARCHIVE_MATCH_CONTEXT];
        id<ReportType> type = op.matchedReportType;
        if (type) {
            // TODO: queue unzip op and add as dependency to import process ops
//            UnzipOperation *unzip = [[UnzipOperation alloc] initWithZipFile:(OZZipFile *)op.reportArchive destDir:_reportsDir fileManager:_fileManager];
        }
        else {
            op.report.error = @"Unkown content type";
        }
    }
}

#pragma mark - ImportDelegate methods

- (void)reportWasUpdatedByImportProcess:(ImportProcess *)import
{
    // TODO: dispatch notifications
}

- (void)importDidFinishForImportProcess:(ImportProcess *)import
{
    // TODO: assign reportID if nil
    // TODO: parse the json descriptor here?
    dispatch_async(dispatch_get_main_queue(), ^{
        // import probably changed the report url, so remove by searching for the report itself
        NSArray *urls = [_pendingImports allKeysForObject:import.report];
        [_pendingImports removeObjectsForKeys:urls];
        import.report.isEnabled = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:[ReportNotification reportImportFinished] object:self userInfo:@{@"report": import.report}];
    });
}

#pragma mark - private_methods

- (nullable Report *)reportAtPath:(NSURL *)path
{
    // TODO: this seems superfluous because the report would be in the reports array already anyway; maybe remove _pendingImports
    Report *report = _pendingImports[path];

    if (report) {
        return report;
    }

    // TODO: check if report url is child of reports directory as well
    for (Report *candidate in self.reports) {
        if ([candidate.url isEqual:path]) {
            return candidate;
        }
    }

    return nil;
}

@end
