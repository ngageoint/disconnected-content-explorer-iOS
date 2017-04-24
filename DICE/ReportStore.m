//
//  ReportStore.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import "ImportProcess.h"
#import "DICEDownloadManager.h"
#import "ReportStore.h"
#import "InspectReportArchiveOperation.h"
#import "MatchReportTypeToContentAtPathOperation.h"
#import "ImportProcess+Internal.h"
#import "NSString+PathUtils.h"
#import "UnzipOperation.h"
#import "DICEDefaultArchiveFactory.h"
#import "Report.h"
#import "ReportType.h"
#import "DICEUtiExpert.h"
#import "DICEExtractReportOperation.h"
#import "FileOperations.h"


@interface PendingImport : NSObject

@property NSURL *sourceUrl;
@property Report *report;
@property ImportProcess *importProcess;

- (instancetype)initWithReport:(Report *)report;

@end


@implementation PendingImport

- (instancetype)initWithReport:(Report *)report
{
    self = [super init];
    self.sourceUrl = report.rootResource;
    self.report = report;
    return self;
}

@end


@interface NSMutableDictionary (PendingImport)

- (PendingImport *)pendingImportWithReport:(Report *)report;
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
+ (NSString *)reportDownloadProgress {
    return @"DICE.ReportDownloadProgress";
}
+ (NSString *)reportDownloadComplete
{
    return @"DICE.ReportDownloadComplete";
}
+ (NSString *)reportImportFinished {
    return @"DICE.ReportImportFinished";
}
+ (NSString *)reportChanged {
    return @"DICE.ReportChanged";
}
+ (NSString *)reportRemoved {
    return @"DICE.ReportRemoved";
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
    DICEDownloadManager *_downloadManager;
    NSMutableDictionary<NSURL *, PendingImport *> *_pendingImports;
    UIBackgroundTaskIdentifier _importBackgroundTaskId;
    NSURL *_trashDir;
    void *ARCHIVE_MATCH_CONTEXT;
    void *CONTENT_MATCH_CONTEXT;
}

dispatch_once_t _sharedInstanceOnce;
ReportStore *_sharedInstance;

+ (void)setSharedInstance:(ReportStore *)sharedInstance
{
    dispatch_once(&_sharedInstanceOnce, ^{
        _sharedInstance = sharedInstance;
    });
    if (sharedInstance != _sharedInstance) {
        [NSException raise:NSInternalInconsistencyException format:@"shared instance already initialized"];
    }
}

+ (instancetype)sharedInstance
{
    dispatch_once(&_sharedInstanceOnce, ^{
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
    importQueue.qualityOfService = NSQualityOfServiceUtility;
    NSFileManager *fm = [NSFileManager defaultManager];
    UIApplication *app = [UIApplication sharedApplication];

    return [self initWithReportsDir:docsDir
        exclusions:nil
        utiExpert:utiExpert
        archiveFactory:archiveFactory
        importQueue:importQueue
        fileManager:fm
        notifications:NSNotificationCenter.defaultCenter
        application:app];
}

- (instancetype)initWithReportsDir:(NSURL *)reportsDir
    exclusions:(NSArray *)exclusions
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
    _trashDir = [_reportsDir URLByAppendingPathComponent:@".dice.trash" isDirectory:YES];

    if (exclusions == nil) {
        exclusions = [NSMutableArray array];
    }
    NSPredicate *excludeTrashDir = [NSPredicate predicateWithFormat:@"%K LIKE %@", @"lastPathComponent", _trashDir.lastPathComponent];
    NSMutableArray *predicates = [NSMutableArray arrayWithCapacity:exclusions.count + 1];
    [predicates addObject:excludeTrashDir];
    [predicates addObjectsFromArray:exclusions];
    _reportsDirExclusions = [NSCompoundPredicate orPredicateWithSubpredicates:predicates];

    ARCHIVE_MATCH_CONTEXT = &ARCHIVE_MATCH_CONTEXT;
    CONTENT_MATCH_CONTEXT = &CONTENT_MATCH_CONTEXT;

    return self;
}

- (void)setDownloadManager:(DICEDownloadManager *)downloadManager
{
    _downloadManager = downloadManager;
}

- (DICEDownloadManager *)downloadManager
{
    return _downloadManager;
}

- (void)addReportsDirExclusion:(NSPredicate *)rule
{
    NSArray *subpredicates = [self.reportsDirExclusions.subpredicates arrayByAddingObject:rule];
    _reportsDirExclusions = [NSCompoundPredicate orPredicateWithSubpredicates:subpredicates];
}

- (NSArray *)loadReports
{
    // TODO: ensure this does not get called more than once concurrently - main thread only
    // TODO: remove deleted reports from list
    NSIndexSet *defunctReports = [_reports indexesOfObjectsPassingTest:^BOOL(Report *report, NSUInteger idx, BOOL *stop) {
        if ([_fileManager fileExistsAtPath:report.rootResource.path]) {
            return NO;
        }
        if (_pendingImports[report.rootResource] != nil) {
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

    NSArray *files = [self.fileManager contentsOfDirectoryAtURL:self.reportsDir includingPropertiesForKeys:@[NSURLFileResourceTypeKey] options:0 error:nil];
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
            isDir = [NSURLFileResourceTypeDirectory isEqualToString:fileType];
        }
        NSString *fileName = [file.lastPathComponent stringByRemovingPercentEncoding];
        NSURL *reportUrl = [self.reportsDir URLByAppendingPathComponent:fileName isDirectory:isDir];

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
    if ([self.reportsDirExclusions evaluateWithObject:reportUrl]) {
        return nil;
    }

    Report *report = [self reportForUrl:reportUrl];
    if (report) {
        if (report.importStatus == ReportImportStatusFailed) {
            [self initializeReport:report forSourceUrl:reportUrl];
        }
        else {
            return report;
        }
    }
    else {
        report = [self addNewPendingReportForUrl:reportUrl];
    }

    if (report.importStatus == ReportImportStatusNewLocal) {
        [self beginInspectingFileForReport:report withUti:NULL];
    }
    else if (report.importStatus == ReportImportStatusNewRemote) {
        report.importStatus = ReportImportStatusDownloading;
        [self.downloadManager downloadUrl:reportUrl];
    }

    return report;
}

- (Report *)initializeReport:(Report *)report forSourceUrl:(NSURL *)url
{
    report.rootResource = url;
    report.baseDir = nil;
    report.downloadProgress = 0;
    report.downloadSize = 0;
    report.isEnabled = NO;
    report.lat = nil;
    report.lon = nil;
    report.reportID = nil;
    report.statusMessage = nil;
    report.summary = nil;
    report.thumbnail = nil;
    report.tileThumbnail = nil;
    report.title = nil;
    report.uti = NULL;

    if ([url.scheme.lowercaseString hasPrefix:@"http"]) {
        report.importStatus = ReportImportStatusNewRemote;
        report.title = report.statusMessage = @"Downloading...";
        report.summary = url.absoluteString;
    }
    else if (url.isFileURL) {
        report.importStatus = ReportImportStatusNewLocal;
        report.title = url.lastPathComponent;
        report.uti = [self.utiExpert preferredUtiForExtension:url.pathExtension conformingToUti:NULL];
        // TODO: do this in background for FS access; move after creating and adding report
        NSDictionary<NSFileAttributeKey, id> *attrs = [self.fileManager attributesOfItemAtPath:url.path error:nil];
        NSString *fileType = attrs.fileType;
        if ([NSFileTypeDirectory isEqualToString:fileType]) {
            report.baseDir = url;
        }
    }

    return report;
}

/**
 * Add a new report record and PendingReport place holder for the given URL, then serially post a
 * ReportAdded notification.
 * @param reportUrl
 * @return
 */
- (Report *)addNewPendingReportForUrl:(NSURL *)reportUrl
{
    Report *report = [self initializeReport:[[Report alloc] init] forSourceUrl:reportUrl];
    [_reports addObject:report];

    // TODO: report is added here but might not be imported;
    // maybe update report to reflect status but leave in list so user can choose to delete it
    _pendingImports[reportUrl] = [[PendingImport alloc] initWithReport:report];

    [self.notifications postNotificationName:[ReportNotification reportAdded] object:self userInfo:@{@"report": report}];

    return report;
}

- (void)beginInspectingFileForReport:(Report *)report withUti:(CFStringRef)reportUti
{
    report.summary = @"Inspecting new content";

    // TODO: identify the task name for the report, or just use one task for all pending imports?
    if (_importBackgroundTaskId == UIBackgroundTaskInvalid) {
        _importBackgroundTaskId = [self.application beginBackgroundTaskWithName:@"dice.background_import" expirationHandler:^{
            [self suspendAndClearPendingImports];
            [self finishBackgroundTaskIfImportsFinished];
        }];
    }

    if (reportUti == NULL) {
        reportUti = [self.utiExpert preferredUtiForExtension:report.rootResource.pathExtension conformingToUti:NULL];
    }

    if ([self.utiExpert uti:reportUti conformsToUti:kUTTypeZipArchive]) {
        // get zip file listing on background thread
        // find appropriate report type for archive contents
        id<DICEArchive> archive = [self.archiveFactory createArchiveForResource:report.rootResource withUti:reportUti];
        InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:self.reportTypes utiExpert:self.utiExpert];
        [op addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:0 context:ARCHIVE_MATCH_CONTEXT];
        [self.importQueue addOperation:op];
    }
    else {
        // TODO: incorporate report uti here as well
        MatchReportTypeToContentAtPathOperation *op =
            [[MatchReportTypeToContentAtPathOperation alloc] initWithReport:report candidateTypes:self.reportTypes];
        [op addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:0 context:CONTENT_MATCH_CONTEXT];
        [self.importQueue addOperation:op];
    }
}

- (void)downloadManager:(DICEDownloadManager *)downloadManager didReceiveDataForDownload:(DICEDownload *)download
{
    Report *report = [self getOrAddReportForDownload:download];
    if (download.percentComplete == report.downloadProgress) {
        return;
    }
    report.title = [NSString stringWithFormat:@"Downloading... %li%%", (long)download.percentComplete];
    report.downloadProgress = (NSUInteger) download.percentComplete;
    [self.notifications postNotificationName:ReportNotification.reportDownloadProgress object:self userInfo:@{@"report": report}];
}

- (NSURL *)downloadManager:(DICEDownloadManager *)downloadManager willFinishDownload:(DICEDownload *)download movingToFile:(NSURL *)destFile
{
    Report *report = [self getOrAddReportForDownload:download];
    report.rootResource = destFile;
    return nil;
}

- (void)downloadManager:(DICEDownloadManager *)downloadManager didFinishDownload:(DICEDownload *)download
{
    if (downloadManager.isFinishingBackgroundEvents) {
        // the app was launched into the background to finish background downloads, so defer expensive
        // import of downloaded files until the user next launches the application
        return;
    }

    Report *report = [self getOrAddReportForDownload:download];

    if (!download.wasSuccessful || download.downloadedFile == nil) {
        // TODO: mechanism to retry
        report.title = @"Download failed";
        report.importStatus = ReportImportStatusFailed;
        report.statusMessage = download.errorMessage;
        report.isEnabled = NO;
        [self clearPendingImportsForReport:report];
        [self.notifications postNotificationName:ReportNotification.reportImportFinished object:self userInfo:@{@"report": report}];
        return;
    }

    report.title = download.downloadedFile.lastPathComponent;
    report.importStatus = ReportImportStatusNewLocal;
    report.statusMessage = @"Download complete";
    report.downloadProgress = 100;
    /*
     * TODO: better utilise the uti expert to make a more intelligent decision based on the best, most specific
     * information available from mime type and file name, and predetermine if a report type might support a uti.
     * e.g., the example report from https://github.com/ngageoint/disconnected-content-explorer-examples/raw/master/reportzips/metromap.zip
     * has a mime type of application/octet-stream and the resulting uti is public.data.  given that, it is
     * more optimal to use the file name to determine the uti.  however, not all downloads might provide a useful
     * file name either, so there should also be a mechanism to make an attempt to import a resource given only a uti
     * like public.data, possibly even user intervention.  this will require some static prioritization of preferred
     * utis, e.g.,
     */
    CFStringRef uti = [self.utiExpert probableUtiForResource:report.rootResource conformingToUti:NULL];
    if ((uti == NULL || [self.utiExpert isDynamicUti:uti]) && download.mimeType) {
        uti = [self.utiExpert preferredUtiForMimeType:download.mimeType conformingToUti:NULL];
    }
    if (uti == NULL || [self.utiExpert uti:uti isEqualToUti:kUTTypeData]) {
        uti = kUTTypeZipArchive;
    }
    if (uti == NULL) {
        uti = kUTTypeItem;
    }

    // TODO: fail on null or dynamic uti?
    [self beginInspectingFileForReport:report withUti:uti];
    [self.notifications postNotificationName:ReportNotification.reportDownloadComplete object:self userInfo:@{@"report": report}];
}

/**
 * Retrieve or create a report record for the given download.
 * @param download
 * @return
 */
- (Report *)getOrAddReportForDownload:(DICEDownload *)download
{
    Report *report = [self reportForUrl:download.url];
    if (report) {
        return report;
    }
    report = [self addNewPendingReportForUrl:download.url];
    report.importStatus = ReportImportStatusDownloading;
    return report;
}

- (Report *)reportForID:(NSString *)reportID
{
    return [self.reports filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"reportID == %@", reportID]].firstObject;
}

- (void)deleteReport:(Report *)report
{
    // TODO: update status message if report cannot be deleted
    if (![self.reports containsObject:report]) {
        return;
    }
    if (!report.isImportFinished) {
        return;
    }
    report.isEnabled = NO;
    report.importStatus = ReportImportStatusDeleting;
    report.statusMessage = @"Deleting content...";
    [self.notifications postNotificationName:ReportNotification.reportChanged object:self userInfo:@{@"report": report}];
    [self scheduleDeleteContentsOfReport:report];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)context
{
    [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) context:context];
    // extract archive or get matched report type
    Report *report;
    if (context == CONTENT_MATCH_CONTEXT) {
        MatchReportTypeToContentAtPathOperation *op = object;
        report = op.report;
        id<ReportType> type = op.matchedReportType;
        if (type) {
            NSLog(@"matched report type %@ to report %@", type, report);
            [self.importQueue addOperationWithBlock:^{
                [self importReport:report asReportType:type];
            }];
            return;
        }
    }
    else if (context == ARCHIVE_MATCH_CONTEXT) {
        InspectReportArchiveOperation *op = object;
        report = op.report;
        id<ReportType> type = op.matchedPredicate.reportType;
        if (type) {
            NSLog(@"matched report type %@ to report archive %@", type, report);
            [self.importQueue addOperationWithBlock:^{
                [self extractReportArchive:op.reportArchive withBaseDir:op.archiveBaseDir forReport:op.report ofType:type];
            }];
            return;
        }
    }

    NSLog(@"no report type found for report archive %@", report);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self clearPendingImportsForReport:report];
        report.summary = @"Unknown content type";
        report.importStatus = ReportImportStatusFailed;
        [self.notifications postNotificationName:ReportNotification.reportImportFinished object:self userInfo:@{@"report": report}];
    });
}

#pragma mark - ImportDelegate methods

- (void)reportWasUpdatedByImportProcess:(ImportProcess *)import
{
    // TODO: notifications
}

- (void)importDidFinishForImportProcess:(ImportProcess *)import
{
    NSDictionary *descriptor = [self parseJsonDescriptorIfAvailableForReport:import.report];
    // TODO: assign reportID if nil
    dispatch_async(dispatch_get_main_queue(), ^{
        // import probably changed the report url, so remove by searching for the report itself
        Report *report = import.report;
        // TODO: leave failed imports so user can decide what to do, retry, delete, etc?
        [self clearPendingImportsForReport:report];
        if (import.wasSuccessful) {
            if (descriptor) {
                [report setPropertiesFromJsonDescriptor:descriptor];
            }
            // TODO: this is a hack to ensure only nilling the summary if the import process didn't change it until
            // the ui changes to use the statusMessage property instead of just summary.  then, ReportStore won't
            // bother ever setting the summary and just set statusMessage instead.
            else if ([@"Importing content..." isEqualToString:report.summary]) {
                report.summary = nil;
            }
            report.isEnabled = YES;
            report.importStatus = ReportImportStatusSuccess;
            report.statusMessage = @"Import complete";
        }
        else {
            report.isEnabled = NO;
            report.importStatus = ReportImportStatusFailed;
            report.summary = report.statusMessage = @"Failed to import content";
        }
        [self.notifications postNotificationName:[ReportNotification reportImportFinished] object:self userInfo:@{@"report": import.report}];
    });
}

#pragma mark - private_methods

- (nullable Report *)reportForUrl:(NSURL *)pathUrl
{
    PendingImport *pendingImport = _pendingImports[pathUrl];

    if (pendingImport) {
        return pendingImport.report;
    }

    NSString *urlStr = pathUrl.absoluteString;
    for (Report *candidate in self.reports) {
        if ([urlStr isEqualToString:candidate.rootResource.absoluteString] ||
            [urlStr isEqualToString:candidate.rootResource.absoluteString] ||
            [urlStr isEqualToString:candidate.baseDir.absoluteString]) {
            return candidate;
        }
        else if (pathUrl.isFileURL) {
            if (candidate.rootResource && [candidate.rootResource.path descendsFromPath:pathUrl.path]) {
                return candidate;
            }
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
        NSString *baseName = [NSString stringWithFormat:@"%@.dicex", report.rootResource.path.lastPathComponent];
        extractToDir = [extractToDir URLByAppendingPathComponent:baseName isDirectory:YES];
        NSError *mkdirError;
        if (![self.fileManager createDirectoryAtURL:extractToDir withIntermediateDirectories:NO attributes:nil error:&mkdirError]) {
            report.summary = [NSString stringWithFormat:@"Error creating base directory for package %@: %@", report.title, mkdirError.localizedDescription];
        }
        baseDir = baseName;
    }
    NSURL *baseDirUrl = [self.reportsDir URLByAppendingPathComponent:baseDir isDirectory:YES];
    // TODO: initialize with already calculated total extracted size
    DICEExtractReportOperation *extract = [[DICEExtractReportOperation alloc]
        initWithReport:report reportType:reportType extractedBaseDir:baseDirUrl
        archive:archive extractToDir:extractToDir fileManager:self.fileManager];
    extract.delegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        PendingImport *pendingImport = [_pendingImports pendingImportWithReport:extract.report];
        _pendingImports[extract.extractedReportBaseDir] = pendingImport;
        report.baseDir = baseDirUrl;
        report.importStatus = ReportImportStatusExtracting;
        // TODO: really just a hack to get the ui to update before extraction actually begins, but probably not even necessary
        [self.notifications postNotificationName:ReportNotification.reportExtractProgress object:self userInfo:@{@"report": report, @"percentExtracted": @(0)}];
        [self.importQueue addOperation:extract];
    });
}

- (void)unzipOperation:(UnzipOperation *)op didUpdatePercentComplete:(NSUInteger)percent
{
    dispatch_async(dispatch_get_main_queue(), ^{
        Report *report = [self reportForUrl:op.archive.archiveUrl];
        report.summary = [NSString stringWithFormat:@"Extracting - %@%%", @(percent)];
        [self.notifications
            postNotificationName:ReportNotification.reportExtractProgress
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
        [self importReport:report asReportType:reportType];
    }];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!success) {
            report.summary = @"Failed to extract archive contents";
            report.importStatus = ReportImportStatusFailed;
            [self.notifications postNotificationName:ReportNotification.reportImportFinished object:self userInfo:@{@"report": report}];
            return;
        }
        report.rootResource = baseDir;
        [self.importQueue addOperation:createImportProcess];
    });
}

- (void)importReport:(Report *)report asReportType:(id<ReportType>)type
{
    NSLog(@"creating import process for report %@", report);
    ImportProcess *importProcess = [type createProcessToImportReport:report toDir:self.reportsDir];
    // TODO: check nil importProcess
    importProcess.delegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        PendingImport *pendingImport = [_pendingImports pendingImportWithReport:report];
        pendingImport.importProcess = importProcess;
        report.importStatus = ReportImportStatusImporting;
        report.summary = report.statusMessage = @"Importing content...";
        [self.notifications postNotificationName:ReportNotification.reportImportBegan object:self userInfo:@{@"report": report}];
        [self.importQueue addOperations:importProcess.steps waitUntilFinished:NO];
    });
}

- (void)clearPendingImportsForReport:(Report *)report
{
    NSArray *urls = [_pendingImports allKeysForReport:report];
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

- (NSDictionary *)parseJsonDescriptorIfAvailableForReport:(Report *)report
{
    NSString *baseDir = [report.rootResource.path pathRelativeToPath:self.reportsDir.path];
    if (baseDir == nil) {
        return nil;
    }
    baseDir = baseDir.pathComponents.firstObject;
    NSString *descriptorPath = [baseDir stringByAppendingPathComponent:@"dice.json"];
    descriptorPath = [self.reportsDir.path stringByAppendingPathComponent:descriptorPath];
    NSData *jsonData = [self.fileManager contentsAtPath:descriptorPath];
    if (jsonData == nil) {
        descriptorPath = [baseDir stringByAppendingPathComponent:@"metadata.json"];
        descriptorPath = [self.reportsDir.path stringByAppendingPathComponent:descriptorPath];
        jsonData = [self.fileManager contentsAtPath:descriptorPath];
    }
    if (jsonData == nil || jsonData.length == 0) {
        return nil;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    return json;
}

- (void)scheduleDeleteContentsOfReport:(Report *)report
{
    NSURL *contentUrl = report.baseDir;
    if (contentUrl == nil) {
        contentUrl = report.rootResource;
    }
    NSString *trashName = [NSUUID UUID].UUIDString;
    NSURL *trashUrl = [_trashDir URLByAppendingPathComponent:trashName isDirectory:YES];
    NSString *contentRelName = [contentUrl.path pathRelativeToPath:self.reportsDir.path];
    NSURL *trashContentUrl = [trashUrl URLByAppendingPathComponent:contentRelName];

    MkdirOperation *makeTrashDir = [[MkdirOperation alloc] initWithDirUrl:trashUrl fileManager:self.fileManager];
    makeTrashDir.queuePriority = NSOperationQueuePriorityHigh;
    makeTrashDir.qualityOfService = NSQualityOfServiceUserInitiated;

    MoveFileOperation *moveToTrash = [[MoveFileOperation alloc] initWithSourceUrl:contentUrl destUrl:trashContentUrl fileManager:self.fileManager];
    moveToTrash.queuePriority = NSOperationQueuePriorityHigh;
    moveToTrash.qualityOfService = NSQualityOfServiceUserInitiated;
    [moveToTrash addDependency:makeTrashDir];

    DeleteFileOperation *deleteFromTrash = [[DeleteFileOperation alloc] initWithFileUrl:nil fileManager:self.fileManager];
    deleteFromTrash.queuePriority = NSOperationQueuePriorityLow;
    deleteFromTrash.qualityOfService = NSQualityOfServiceBackground;
    [deleteFromTrash addDependency:moveToTrash];
    
    __weak MoveFileOperation *moveToTrashCompleted = moveToTrash;
    moveToTrash.completionBlock = ^{
        if (!moveToTrashCompleted.fileWasMoved) {
            [deleteFromTrash cancel];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [_reports removeObject:report];
            deleteFromTrash.fileUrl = trashUrl;
            [self.notifications postNotificationName:ReportNotification.reportRemoved object:self userInfo:@{@"report": report}];
        });
    };

    deleteFromTrash.completionBlock = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            report.importStatus = ReportImportStatusDeleted;
        });
    };

    [self.importQueue addOperations:@[makeTrashDir, moveToTrash, deleteFromTrash] waitUntilFinished:NO];
}

@end
