//
//  ReportStore.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import "ImportProcess.h"
#import "ReportStore.h"
#import "InspectReportArchiveOperation.h"
#import "MatchReportTypeToContentAtPathOperation.h"
#import "ImportProcess+Internal.h"
#import "UnzipOperation.h"
#import "DICEDefaultArchiveFactory.h"
#import "Report.h"
#import "ReportType.h"
#import "DICEUtiExpert.h"
#import "DICEExtractReportOperation.h"


@interface PendingImport : NSObject

@property NSURL *sourceUrl;
@property Report *report;
@property id<DICEArchive> archive;
@property NSURL *extractedBaseDir;
@property ImportProcess *importProcess;

- (instancetype)initWithSourceUrl:(NSURL *)url Report:(Report *)report;

@end


@implementation PendingImport

- (instancetype)initWithSourceUrl:(NSURL *)url Report:(Report *)report
{
    self = [super init];
    self.sourceUrl = url;
    self.report = report;
    return self;
}

@end


@interface NSMutableDictionary (PendingImport)

- (PendingImport *)pendingImportWithReport:(Report *)report;
- (PendingImport *)pendingImportForReportUrl:(NSURL *)reportUrl;
- (NSArray *)allKeysForReport:(Report *)report;

@end


@implementation NSMutableDictionary (PendingImport)

- (PendingImport *)pendingImportWithReport:(Report *)report
{
    for (PendingImport *pi in self.allValues) {
        if (pi.report == report) {
            return pi;
        }
    }
    return nil;
}

- (PendingImport *)pendingImportForReportUrl:(NSURL *)reportUrl
{
    for (PendingImport *pi in self.allValues) {
        if ([pi.report.url isEqual:reportUrl]) {
            return pi;
        }
    }
    return nil;
}

- (NSArray *)allKeysForReport:(Report *)report
{
    return [self.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id _Nullable key, NSDictionary<NSString *,id> * _Nullable bindings) {
        PendingImport *pi = self[key];
        return pi.report == report;
    }]];
}

@end


@implementation ReportNotification

+ (NSString *)reportAdded {
    return @"DICE.ReportAdded";
}
+ (NSString *)reportImportBegan {
    return @"DICE.ReportImportBegan";
}
+ (NSString *)reportExtractProgress {
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


@interface ReportStore () <UnzipDelegate>
@end


// TODO: thread safety for reports array
@implementation ReportStore
{
    NSMutableArray<Report *> *_reports;
    NSMutableDictionary<NSURL *, PendingImport *> *_pendingImports;
    UIBackgroundTaskIdentifier _importBackgroundTaskId;
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
    id<DICEArchiveFactory> archiveFactory = [[DICEDefaultArchiveFactory alloc] initWithUtiExpert:utiExpert];
    NSOperationQueue *importQueue = [[NSOperationQueue alloc] init];
    NSFileManager *fm = [NSFileManager defaultManager];
    UIApplication *app = [UIApplication sharedApplication];
    
    return [self initWithReportsDir:docsDir
        utiExpert:utiExpert
        archiveFactory:archiveFactory
        importQueue:importQueue
        fileManager:fm
        notifications:NSNotificationCenter.defaultCenter
        application:app];
}

- (instancetype)initWithReportsDir:(NSURL *)reportsDir
    utiExpert:(DICEUtiExpert *)utiExpert
    archiveFactory:(id<DICEArchiveFactory>)archiveFactory
    importQueue:(NSOperationQueue *)importQueue
    fileManager:(NSFileManager *)fileManager
    notifications:(NSNotificationCenter *)notifications
    application:(UIApplication *)application
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _reports = [NSMutableArray array];
    _pendingImports = [NSMutableDictionary dictionary];
    _reportsDir = reportsDir;
    _utiExpert = utiExpert;
    _archiveFactory = archiveFactory;
    _importQueue = importQueue;
    _fileManager = fileManager;
    _notifications = notifications;
    _application = application;
    _importBackgroundTaskId = UIBackgroundTaskInvalid;
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
        if ([_pendingImports pendingImportWithReport:report]) {
            return NO;
        }
        return YES;
    }];
    if (defunctReports.count > 0) {
        [_reports removeObjectsAtIndexes:defunctReports];
        // TODO: dispatch reports changed notification, or just wait till load is complete
    }

    NSArray *files = [self.fileManager contentsOfDirectoryAtURL:self.reportsDir includingPropertiesForKeys:nil options:0 error:nil];
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
        BOOL isDir = [file.absoluteString hasSuffix:@"/"];
        if (!isDir) {
            NSString *fileType;
            [file getResourceValue:&fileType forKey:NSURLFileResourceTypeKey error:NULL];
            [NSURLFileResourceTypeDirectory isEqualToString:fileType];
        }
        NSString *fileName = [file.lastPathComponent stringByRemovingPercentEncoding];
        NSURL *reportUrl = [self.reportsDir URLByAppendingPathComponent:fileName isDirectory:isDir];

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
        [self.notifications
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

    CFStringRef reportUti = [self.utiExpert preferredUtiForExtension:reportUrl.pathExtension conformingToUti:NULL];
    report = [[Report alloc] initWithTitle:reportUrl.path];
    report.isEnabled = NO;
    report.url = reportUrl;
    report.uti = reportUti;
    report.title = reportUrl.lastPathComponent;
    report.summary = @"Importing...";

    // TODO: identify the task name for the report, or just use one task for all pending imports?
    if (_importBackgroundTaskId == UIBackgroundTaskInvalid) {
        _importBackgroundTaskId = [self.application beginBackgroundTaskWithName:@"dice import" expirationHandler:^{
            [self suspendAndClearPendingImports];
            [self finishBackgroundTaskIfImportsFinished];
        }];
    }

    // TODO: report is added here but might not be imported;
    // maybe update report to reflect status but leave in list so user can choose to delete it
    [_reports addObject:report];
    _pendingImports[reportUrl] = [[PendingImport alloc] initWithSourceUrl:reportUrl Report:report];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.notifications postNotificationName:[ReportNotification reportAdded] object:self userInfo:@{@"report": report}];
    });

    if ([self.utiExpert uti:reportUti conformsToUti:kUTTypeZipArchive]) {
        // get zip file listing on background thread
        // find appropriate report type for archive contents
        id<DICEArchive> archive = [self.archiveFactory createArchiveForResource:reportUrl withUti:reportUti];
        InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:self.reportTypes utiExpert:self.utiExpert];
        [op addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:0 context:ARCHIVE_MATCH_CONTEXT];
        [self.importQueue addOperation:op];
        return report;
    }
    else {
        MatchReportTypeToContentAtPathOperation *op =
            [[MatchReportTypeToContentAtPathOperation alloc] initWithReport:report candidateTypes:self.reportTypes];
        [op addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:0 context:CONTENT_MATCH_CONTEXT];
        [self.importQueue addOperation:op];
    }

    return report;
}

- (Report *)reportForID:(NSString *)reportID
{
    return [self.reports filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"reportID == %@", reportID]].firstObject;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)context
{
    [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) context:context];
    // extract archive or get matched report type
    if (context == CONTENT_MATCH_CONTEXT) {
        MatchReportTypeToContentAtPathOperation *op = object;
        Report *report = op.report;
        id<ReportType> type = op.matchedReportType;
        if (type) {
            NSLog(@"matched report type %@ to report %@", type, report);
            [self.importQueue addOperationWithBlock:^{
                [self startImportProcessForReport:report reportType:type];
            }];
        }
        else {
            NSLog(@"no report type found for report %@", op.report);
            report.error = @"Unkown content type";
        }
    }
    else if (context == ARCHIVE_MATCH_CONTEXT) {
        InspectReportArchiveOperation *op = object;
        Report *report = op.report;
        id<ReportType> type = op.matchedReportType;
        if (type) {
            NSLog(@"matched report type %@ to report archive %@", type, report);
            [self.importQueue addOperationWithBlock:^{
                [self extractReportArchive:op.reportArchive withBaseDir:op.archiveBaseDir forReport:op.report ofType:type];
            }];
        }
        else {
            NSLog(@"no report type found for report archive %@", report);
            report.error = @"Unkown content type";
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
        [self clearPendingImportProcess:import];
        import.report.isEnabled = import.wasSuccessful;
        if (!import.wasSuccessful) {
            import.report.error = @"Failed to import content";
        }
        [self.notifications postNotificationName:[ReportNotification reportImportFinished] object:self userInfo:@{@"report": import.report}];
    });
}

#pragma mark - private_methods

- (nullable Report *)reportAtPath:(NSURL *)path
{
    PendingImport *pendingImport = _pendingImports[path];

    if (pendingImport) {
        return pendingImport.report;
    }

    // TODO: check if report url is child of reports directory as well
    for (Report *candidate in self.reports) {
        if ([candidate.url isEqual:path]) {
            return candidate;
        }
    }

    return nil;
}

- (void)extractReportArchive:(id<DICEArchive>)archive withBaseDir:(NSString *)baseDir forReport:(Report *)report ofType:(id<ReportType>)reportType
{
    NSLog(@"extracting report archive %@", report);
    NSURL *extractToDir = self.reportsDir;
    if (baseDir == nil) {
        // TODO: more robust check for possible conflicting base dirs?
        NSString *baseName = [NSString stringWithFormat:@"%@.dicex", report.url.path.lastPathComponent];
        extractToDir = [extractToDir URLByAppendingPathComponent:baseName isDirectory:YES];
        NSError *mkdirError;
        if (![self.fileManager createDirectoryAtURL:extractToDir withIntermediateDirectories:NO attributes:nil error:&mkdirError]) {
            report.error = [NSString stringWithFormat:@"Error creating base directory for package %@: %@", report.title, mkdirError.localizedDescription];
        }
        baseDir = baseName;
    }
    NSURL *baseDirUrl = [self.reportsDir URLByAppendingPathComponent:baseDir isDirectory:YES];
    DICEExtractReportOperation *extract = [[DICEExtractReportOperation alloc]
        initWithReport:report reportType:reportType extractedBaseDir:baseDirUrl
        archive:archive extractToDir:extractToDir fileManager:self.fileManager];
    extract.delegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        PendingImport *pendingImport = [_pendingImports pendingImportWithReport:extract.report];
        _pendingImports[extract.extractedReportBaseDir] = pendingImport;
        [self.importQueue addOperation:extract];
    });
}

- (void)unzipOperation:(UnzipOperation *)op didUpdatePercentComplete:(NSUInteger)percent
{
    dispatch_async(dispatch_get_main_queue(), ^{
        Report *report = [self reportAtPath:op.archive.archiveUrl];
        report.summary = [NSString stringWithFormat:@"Extracting - %@%%", @(percent)];
        [self.notifications
            postNotificationName:[ReportNotification reportExtractProgress]
            object:self userInfo:@{@"report": report, @"percentExtracted": @(percent)}];
    });
}

- (void)unzipOperationDidFinish:(UnzipOperation *)op
{
    DICEExtractReportOperation *extract = (DICEExtractReportOperation *)op;
    BOOL success = op.wasSuccessful;
    Report *report = extract.report;
    id<ReportType> reportType = extract.reportType;
    NSURL *baseDir = extract.extractedReportBaseDir;

    NSLog(@"finished extracting contents of report archive %@", report);

    NSError *error;
    BOOL deleted = [self.fileManager removeItemAtURL:extract.archive.archiveUrl error:&error];
    if (!deleted) {
        // TODO: something
    }

    NSBlockOperation *createImportProcess = [NSBlockOperation blockOperationWithBlock:^{
        [self startImportProcessForReport:report reportType:reportType];
    }];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!success) {
            report.error = @"Failed to extract archive content";
            return;
        }
        report.url = baseDir;
        report.summary = @"Importing report content...";
        [self.importQueue addOperation:createImportProcess];
    });
}

- (void)startImportProcessForReport:(Report *)report reportType:(id<ReportType>)type
{
    NSLog(@"creating import process for report %@", report);
    ImportProcess *importProcess = [type createProcessToImportReport:report toDir:self.reportsDir];
    // TODO: check nil importProcess
    importProcess.delegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        PendingImport *pendingImport = [_pendingImports pendingImportWithReport:report];
        pendingImport.importProcess = importProcess;
        [self.importQueue addOperations:importProcess.steps waitUntilFinished:NO];
    });
}

- (void)clearPendingImportProcess:(ImportProcess *)import
{
    NSArray *urls = [_pendingImports allKeysForReport:import.report];
    [_pendingImports removeObjectsForKeys:urls];
    [self finishBackgroundTaskIfImportsFinished];
}

- (void)suspendAndClearPendingImports
{
    self.importQueue.suspended = YES;
    NSArray *keys = _pendingImports.allKeys;
    [keys enumerateObjectsUsingBlock:^(id _Nonnull key, NSUInteger idx, BOOL * _Nonnull stop) {
        PendingImport *pi = _pendingImports[key];
        [_pendingImports removeObjectForKey:key];
        if (pi.importProcess == nil) {
            return;
        }
        [pi.importProcess cancel];
    }];

    NSArray<NSOperation *> *ops = self.importQueue.operations;
    [self.importQueue cancelAllOperations];
    for (NSOperation *op in ops) {
        if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
            DICEExtractReportOperation *extract = (DICEExtractReportOperation *)op;
            // TODO: save extract progress instead of removing extracted content
            BOOL removed = [self.fileManager removeItemAtURL:extract.extractedReportBaseDir error:NULL];
            if (!removed) {
                // TODO: something
            }
        }
    }

    self.importQueue.suspended = NO;
}

- (void)finishBackgroundTaskIfImportsFinished
{
    if (_pendingImports.count > 0) {
        return;
    }
    [self.application endBackgroundTask:_importBackgroundTaskId];
    _importBackgroundTaskId = UIBackgroundTaskInvalid;
}

@end
