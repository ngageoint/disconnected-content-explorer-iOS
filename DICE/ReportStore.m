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
#import "DICEDeleteReportProcess.h"
#import "DICEExtractReportOperation.h"
#import "FileOperations.h"
#import "NSURL+ResourceValues.h"

void ensureMainThread() {
    if (!NSThread.isMainThread) {
        [NSException raise:NSInternalInconsistencyException format:@"expected main thread"];
    }
}

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


@implementation Report (ReportStoreDRY)

- (BOOL)isReadyForShutdown
{
    return self.isImportFinished || self.importStatus == ReportImportStatusDownloading;
}

@end


@implementation NSFileManager (ReportStore)

- (BOOL)isDirectoryAtUrl:(NSURL *)url
{
    BOOL isDir;
    return [self fileExistsAtPath:url.path isDirectory:&isDir] && isDir;
}

@end



static NSString *const PersistedRecordName = @"dice.obj";
static NSString *const ImportDirSuffix = @".dice_import";


@interface ReportStore () <UnzipDelegate, DICEDeleteReportProcessDelegate>
@end


// TODO: thread safety for reports array
@implementation ReportStore
{
    NSMutableArray<Report *> *_reports;
    NSMutableArray<ImportProcess *> *_pendingImports;
    DICEDownloadManager *_downloadManager;
    UIBackgroundTaskIdentifier _importBackgroundTaskId;
    NSURL *_contentDir;
    NSURL *_trashDir;
    BOOL _backgroundTimeExpired;
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
    _pendingImports = [NSMutableArray array];
    _reportsDir = reportsDir;
    _utiExpert = utiExpert;
    _archiveFactory = archiveFactory;
    _importQueue = importQueue;
    _fileManager = fileManager;
    _notifications = notifications;
    _application = application;
    _importBackgroundTaskId = UIBackgroundTaskInvalid;
    _trashDir = [_reportsDir URLByAppendingPathComponent:@"dice.trash" isDirectory:YES];
    _backgroundTimeExpired = NO;

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

    // TODO: handle errors more goodly
    NSError *err;
    BOOL created = [_fileManager createDirectoryAtURL:_trashDir withIntermediateDirectories:YES attributes:nil error:&err];
    if (!created) {
        [NSException raise:NSInternalInconsistencyException format:@"error creating trash directory %@: %@", _trashDir, err.localizedDescription];
    }

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
    ensureMainThread();
    // TODO: remove deleted reports from list
    NSIndexSet *defunctReports = [_reports indexesOfObjectsPassingTest:^BOOL(Report *report, NSUInteger idx, BOOL *stop) {
        if ([_fileManager fileExistsAtPath:report.rootFile.path]) {
            return NO;
        }
        if ([_fileManager fileExistsAtPath:report.sourceFile.path]) {
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
            isDir = file.isDirectory.boolValue;
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
    ensureMainThread();

    // TODO: differentiate between new and imported reports (*.dice_import/)
    // here or in loadReports? probably here
    if ([self.reportsDirExclusions evaluateWithObject:reportUrl]) {
        return nil;
    }

    // TODO: assumes reportUrl is in docs directory
    // TODO: check if this report might have been imported before, e.g., from this same url or perhaps a hash, then prompt to overwrite
    Report *report = [self reportForUrl:reportUrl];
    if (report) {
        return report;
    }

    report = [self addNewReportForUrl:reportUrl];
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
    report.sourceFile = nil;
    report.remoteSource = nil;
    report.baseDir = nil;
    report.rootFile = nil;
    report.uti = NULL;
    report.importStatus = ReportImportStatusNew;
    report.downloadProgress = 0;
    report.downloadSize = 0;
    report.isEnabled = NO;
    report.lat = nil;
    report.lon = nil;
    report.contentId = nil;
    report.statusMessage = nil;
    report.summary = nil;
    report.thumbnail = nil;
    report.tileThumbnail = nil;
    report.title = nil;

    if ([url.scheme.lowercaseString hasPrefix:@"http"]) {
        report.remoteSource = url;
        report.importStatus = ReportImportStatusNewRemote;
        report.title = report.statusMessage = @"Downloading...";
        report.summary = url.absoluteString;
    }
    else if (url.isFileURL) {
        report.sourceFile = url;
        report.importStatus = ReportImportStatusNewLocal;
        report.title = url.lastPathComponent;
        report.uti = (__bridge NSString *)[self.utiExpert preferredUtiForExtension:url.pathExtension conformingToUti:NULL];
    }

    return report;
}

/**
 * Add a new report record for the given URL and serially post a ReportAdded notification.
 * @param reportUrl
 * @return
 */
- (Report *)addNewReportForUrl:(NSURL *)reportUrl
{
    ensureMainThread();
    Report *report = [self initializeReport:[[Report alloc] init] forSourceUrl:reportUrl];
    [_reports addObject:report];

    [self.notifications postNotificationName:ReportNotification.reportAdded object:self userInfo:@{@"report": report}];

    return report;
}

- (void)beginInspectingFileForReport:(Report *)report withUti:(CFStringRef)reportUti
{
    ensureMainThread();

    // TODO: identify the task name for the report, or just use one task for all pending imports?
    if (_importBackgroundTaskId == UIBackgroundTaskInvalid) {
        _importBackgroundTaskId = [self.application beginBackgroundTaskWithName:@"dice.background_import" expirationHandler:^{
            _backgroundTimeExpired = YES;
            [self suspendAndClearPendingImports];
        }];
    }

    if ([report.sourceFile.lastPathComponent hasSuffix:ImportDirSuffix]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self loadRecordForReport:report];
            [self.notifications postNotificationName:ReportNotification.reportImportFinished object:self userInfo:@{@"report": report}];
        });
        return;
    }

    report.summary = @"Inspecting new content";

    if (reportUti == NULL) {
        reportUti = [self.utiExpert preferredUtiForExtension:report.sourceFile.pathExtension conformingToUti:NULL];
    }

    if ([self.utiExpert uti:reportUti conformsToUti:kUTTypeZipArchive]) {
        // get zip file listing on background thread
        // find appropriate report type for archive contents
        id<DICEArchive> archive = [self.archiveFactory createArchiveForResource:report.sourceFile withUti:reportUti];
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

- (void)loadRecordForReport:(Report *)report
{
    ensureMainThread();

    NSString *recordPath = [report.sourceFile.path stringByAppendingPathComponent:PersistedRecordName];
    NSData *record = [self.fileManager contentsAtPath:recordPath];
    if (!record) {
        report.summary = report.statusMessage = @"Error loading previously imported content - no record found.";
        report.importStatus = ReportImportStatusFailed;
        return;
    }
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:record];
    [report setPropertiesFromCoder:unarchiver];
    [unarchiver finishDecoding];
}

- (void)saveRecordForReport:(Report *)report
{
    NSMutableData *record = [NSMutableData data];
    NSKeyedArchiver *coder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:record];
    [report encodeWithCoder:coder];
    [coder finishEncoding];
    NSString *recordPath = [report.importDir.path stringByAppendingPathComponent:PersistedRecordName];
    [self.fileManager createFileAtPath:recordPath contents:record attributes:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)context
{
    [object removeObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) context:context];

    // extract archive or get matched report type
    Report *report;
    void (^nextStep)() = nil;
    if (context == CONTENT_MATCH_CONTEXT) {
        MatchReportTypeToContentAtPathOperation *op = object;
        report = op.report;
        id<ReportType> type = op.matchedReportType;
        if (type) {
            NSLog(@"matched report type %@ to report %@", type, report);
            nextStep = ^{
                [self moveSourceFileToImportDirOfReport:report importAsType:type];
            };
        }
    }
    else if (context == ARCHIVE_MATCH_CONTEXT) {
        InspectReportArchiveOperation *op = object;
        report = op.report;
        id<ReportType> type = op.matchedPredicate.reportType;
        if (type) {
            NSLog(@"matched report type %@ to report archive %@", type, report);
            nextStep = ^{
                [self extractReportArchive:op.reportArchive withBaseDir:op.archiveBaseDir forReport:op.report ofType:type];
            };
        }
    }
    else {
        [NSException raise:NSInternalInconsistencyException format:@"unexpected observed value for key path %@ of object %@", keyPath, object];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (nextStep) {
            // TODO: probably fine on main thread, but who knows? possibly move to import queue
            // TODO: normalize to proper file names
            NSError *err = nil;
            NSString *importDirName = [report.sourceFile.lastPathComponent stringByAppendingString:ImportDirSuffix];
            report.importDir = [self.reportsDir URLByAppendingPathComponent:importDirName isDirectory:YES];
            if ([self.fileManager fileExistsAtPath:report.importDir.path]) {
                // TODO: prompt to make new report or overwrite existing
            }
            BOOL created = [self.fileManager createDirectoryAtURL:report.importDir withIntermediateDirectories:YES attributes:nil error:&err];
            if (!created) {
                // TODO: coping with failure
            }
            nextStep();
        }
        else {
            NSLog(@"no report type found for report archive %@", report);
            report.summary = @"Unknown content type";
            report.importStatus = ReportImportStatusFailed;
            [self finishBackgroundTaskIfImportsFinished];
            [self.notifications postNotificationName:ReportNotification.reportImportFinished object:self userInfo:@{@"report": report}];
        }
    });
}

- (void)moveSourceFileToImportDirOfReport:(Report *)report importAsType:(id<ReportType>)reportType
{
    ensureMainThread();

    MoveFileOperation *mv = [[[MoveFileOperation alloc]
        initWithSourceUrl:report.sourceFile destUrl:nil fileManager:self.fileManager] createDestDirs:YES];
    if ([self.fileManager isDirectoryAtUrl:report.sourceFile]) {
        report.baseDir = [report.importDir URLByAppendingPathComponent:report.sourceFile.lastPathComponent isDirectory:YES];
        mv.destUrl = report.baseDir;
    }
    else {
        report.baseDir = [report.importDir URLByAppendingPathComponent:@"dice_content" isDirectory:YES];
        report.rootFile = [report.baseDir URLByAppendingPathComponent:report.sourceFile.lastPathComponent];
        mv.destUrl = report.rootFile;
    }

    __weak MoveFileOperation *mvCaptured = mv;
    void (^afterMove)() = ^{
        if (mvCaptured.fileWasMoved) {
            [self.importQueue addOperationWithBlock:^{
                [self importReport:report asReportType:reportType];
            }];
        }
        else {
            NSLog(@"error moving report source file %@ to %@: %@", report.sourceFile, report.rootFile, mvCaptured.error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                report.importStatus = ReportImportStatusFailed;
                report.statusMessage = [NSString stringWithFormat:@"Error moving source file %@ to import directory: %@",
                    report.sourceFile.lastPathComponent, mvCaptured.error.localizedDescription];
                [self.notifications postNotificationName:ReportNotification.reportImportFinished object:self userInfo:@{@"report": report}];
            });
        }
    };
    mv.completionBlock = afterMove;
    [self.importQueue addOperation:mv];
}

- (void)downloadManager:(DICEDownloadManager *)downloadManager didReceiveDataForDownload:(DICEDownload *)download
{
    ensureMainThread();

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
    ensureMainThread();

    Report *report = [self getOrAddReportForDownload:download];
    report.sourceFile = destFile;
    return nil;
}

- (void)downloadManager:(DICEDownloadManager *)downloadManager didFinishDownload:(DICEDownload *)download
{
    ensureMainThread();

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
        [self finishBackgroundTaskIfImportsFinished];
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
    CFStringRef uti = [self.utiExpert probableUtiForResource:report.sourceFile conformingToUti:NULL];
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
    ensureMainThread();

    Report *report = [self reportForUrl:download.url];
    if (report) {
        return report;
    }
    report = [self addNewReportForUrl:download.url];
    report.importStatus = ReportImportStatusDownloading;
    return report;
}

- (Report *)reportForID:(NSString *)reportID
{
    ensureMainThread();

    return [self.reports filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"contentId == %@", reportID]].firstObject;
}

- (void)deleteReport:(Report *)report
{
    ensureMainThread();

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
    DICEDeleteReportProcess *delReport = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:_trashDir fileManager:self.fileManager];
    delReport.delegate = self;
    [_pendingImports addObject:delReport]; // retain so it doesn't get deallocated
    [self.importQueue addOperations:delReport.steps waitUntilFinished:NO];
}

#pragma mark - ImportDelegate methods

- (void)reportWasUpdatedByImportProcess:(ImportProcess *)import
{
    // TODO: notifications
}

- (void)importDidFinishForImportProcess:(ImportProcess *)importProcess
{
    if ([importProcess isKindOfClass:[DICEDeleteReportProcess class]]) {
        NSLog(@"delete process finished for report %@", importProcess.report);
        // TODO: what if it failed?
        // TODO: worry about background task? we didn't begin one for this import process
        [_pendingImports removeObject:importProcess];
        return;
    }
    NSLog(@"import did finish for report %@", importProcess.report);
    // TODO: only use json descriptor if new import, else use NSCoding serialized Report object
    NSDictionary *descriptor = [self parseJsonDescriptorIfAvailableForReport:importProcess.report];
    // TODO: assign contentId if nil
    dispatch_async(dispatch_get_main_queue(), ^{
        // TODO: leave failed imports so user can decide what to do, retry, delete, etc?
        NSLog(@"finalizing import for report %@", importProcess.report);
        Report *report = importProcess.report;
        if (importProcess.wasSuccessful) {
            if (descriptor) {
                [report setPropertiesFromJsonDescriptor:descriptor];
            }
            // TODO: this is a hack to ensure only nilling the summary if the import process didn't change it until
            // the ui changes to use the statusMessage property instead of just summary.  then, ReportStore won't
            // bother ever setting the summary and just set statusMessage instead.
            else if ([@"Importing content..." isEqualToString:report.summary]) {
                report.summary = nil;
            }
            if (!report.baseDir) {
                report.baseDir = report.importDir;
            }
            if (!report.rootFile) {
                report.rootFile = [report.baseDir URLByAppendingPathComponent:report.sourceFile.lastPathComponent];
            }
            // TODO: check rootFile uti
            NSLog(@"enabling report %@", report);
            report.isEnabled = YES;
            report.importStatus = ReportImportStatusSuccess;
            report.statusMessage = @"Import complete";
        }
        else {
            NSLog(@"disabling report %@ after unsuccessful import", report);
            report.isEnabled = NO;
            report.importStatus = ReportImportStatusFailed;
            report.summary = report.statusMessage = @"Failed to import content";
        }
        [self clearPendingImport:importProcess];
        [self saveRecordForReport:report];
        [self.notifications postNotificationName:ReportNotification.reportImportFinished object:self userInfo:@{@"report": importProcess.report}];
    });
}

#pragma mark - private_methods

- (nullable Report *)reportForUrl:(NSURL *)pathUrl
{
    NSString *urlStr = pathUrl.absoluteString;
    for (Report *candidate in self.reports) {
        if ([urlStr isEqualToString:candidate.rootFile.absoluteString] ||
            [urlStr isEqualToString:candidate.importDir.absoluteString] ||
            [urlStr isEqualToString:candidate.sourceFile.absoluteString] ||
            [urlStr isEqualToString:candidate.remoteSource.absoluteString] ||
            [urlStr isEqualToString:candidate.baseDir.absoluteString]) {
            return candidate;
        }
        else if (pathUrl.isFileURL) {
            if (candidate.rootFile && [candidate.rootFile.path descendsFromPath:pathUrl.path]) {
                return candidate;
            }
        }
    }

    return nil;
}

/**
 * invoke on main thread
 */
- (void)extractReportArchive:(id<DICEArchive>)archive withBaseDir:(NSString *)baseDir forReport:(Report *)report ofType:(id<ReportType>)reportType
{
    ensureMainThread();
    NSLog(@"extracting report archive %@", report);
    NSURL *extractToDir = report.importDir;
    if (baseDir == nil) {
        // TODO: more robust check for possible conflicting base dirs?
        baseDir = @"dice_content";
        extractToDir = [extractToDir URLByAppendingPathComponent:baseDir isDirectory:YES];
        NSError *mkdirError;
        if (![self.fileManager createDirectoryAtURL:extractToDir withIntermediateDirectories:NO attributes:nil error:&mkdirError]) {
            report.summary = [NSString stringWithFormat:@"Error creating base directory for report %@: %@", report.title, mkdirError.localizedDescription];
        }
    }
    NSURL *baseDirUrl = [report.importDir URLByAppendingPathComponent:baseDir isDirectory:YES];
    report.baseDir = baseDirUrl;
    // TODO: initialize with already calculated total extracted size
    DICEExtractReportOperation *extract = [[DICEExtractReportOperation alloc]
        initWithReport:report reportType:reportType extractedBaseDir:baseDirUrl
        archive:archive extractToDir:extractToDir fileManager:self.fileManager];
    extract.delegate = self;
    report.importStatus = ReportImportStatusExtracting;
    // TODO: really just a hack to get the ui to update before extraction actually begins, but probably not even necessary
    [self.notifications postNotificationName:ReportNotification.reportExtractProgress object:self userInfo:@{@"report": report, @"percentExtracted": @(0)}];
    [self.importQueue addOperation:extract];
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

    if (!success) {
        NSLog(@"extraction of archive %@ was not successful", report.sourceFile);
        dispatch_async(dispatch_get_main_queue(), ^{
            report.summary = report.statusMessage = @"Failed to extract archive contents";
            report.importStatus = ReportImportStatusFailed;
            [self finishBackgroundTaskIfImportsFinished];
            [self.notifications postNotificationName:ReportNotification.reportImportFinished object:self userInfo:@{@"report": report}];
        });
        return;
    }

    NSBlockOperation *createImportProcess = [NSBlockOperation blockOperationWithBlock:^{
        [self importReport:report asReportType:reportType];
    }];
    DeleteFileOperation *deleteArchive = [[DeleteFileOperation alloc] initWithFileUrl:extract.archive.archiveUrl fileManager:self.fileManager];

    dispatch_async(dispatch_get_main_queue(), ^{
        report.baseDir = baseDir;
        [self.importQueue addOperation:createImportProcess];
        [self.importQueue addOperation:deleteArchive];
    });
}

- (void)importReport:(Report *)report asReportType:(id<ReportType>)type
{
    NSLog(@"creating import process for report %@", report);
    ImportProcess *importProcess = [type createProcessToImportReport:report toDir:self.reportsDir];
    // TODO: check nil importProcess
    importProcess.delegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"queuing import process for report %@", report);
        [_pendingImports addObject:importProcess];
        report.importStatus = ReportImportStatusImporting;
        report.summary = report.statusMessage = @"Importing content...";
        [self.notifications postNotificationName:ReportNotification.reportImportBegan object:self userInfo:@{@"report": report}];
        [self.importQueue addOperations:importProcess.steps waitUntilFinished:NO];
    });
}

- (void)clearPendingImport:(ImportProcess *)importProcess
{
    NSLog(@"clearing pending import for report %@, pending imports remainging %lu", importProcess.report, (unsigned long) _pendingImports.count);
    NSUInteger pos = [_pendingImports indexOfObject:importProcess];
    if (pos == NSNotFound) {
        if (_importBackgroundTaskId != UIBackgroundTaskInvalid) {
            [NSException raise:NSInternalInconsistencyException format:
                @"attempt to remove pending import process for report %@, but there was no such process", importProcess.report];
        }
    }
    else {
        [_pendingImports removeObjectAtIndex:pos];
        [self finishBackgroundTaskIfImportsFinished];
    }
}

- (void)suspendAndClearPendingImports
{
    self.importQueue.suspended = YES;

    for (ImportProcess *importProcess in _pendingImports) {
        [importProcess cancel];
    }
    [_pendingImports removeAllObjects];

    for (Report *report in _reports) {
        if (!report.isReadyForShutdown) {
            report.importStatus = ReportImportStatusFailed;
        }
    }

    NSArray<NSOperation *> *ops = self.importQueue.operations;
    [self.importQueue cancelAllOperations];
    for (NSOperation *op in ops) {
        if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
            DICEExtractReportOperation *extract = (DICEExtractReportOperation *)op;
            // TODO: save extract progress instead of removing extracted content
            // TODO: move to trash instead of deleting
            // TODO: move to background thread
            BOOL removed = [self.fileManager removeItemAtURL:extract.extractedReportBaseDir error:NULL];
            if (!removed) {
                // TODO: something
            }
        }
    }

    [self endBackgroundTask];
}

- (void)finishBackgroundTaskIfImportsFinished
{
    if (_pendingImports.count > 0) {
        return;
    }
    NSUInteger pendingReport = [_reports indexOfObjectPassingTest:^BOOL(Report *report, NSUInteger idx, BOOL *stop) {
        return !report.isReadyForShutdown;
    }];
    if (pendingReport != NSNotFound) {
        return;
    }

    [self endBackgroundTask];
}

- (void)endBackgroundTask
{
    if (_importBackgroundTaskId == UIBackgroundTaskInvalid) {
        [NSException raise:NSInternalInconsistencyException
            format:@"multiple attempts to end the background task - no pending imports remain but background task id is invalid"];
    }
    NSLog(@"ending background task %lu", (unsigned long) _importBackgroundTaskId);
    [self.application endBackgroundTask:_importBackgroundTaskId];
    _importBackgroundTaskId = UIBackgroundTaskInvalid;
}

- (void)appDidEnterBackground
{

}

- (void)appWillEnterForeground
{
    
}

- (NSDictionary *)parseJsonDescriptorIfAvailableForReport:(Report *)report
{
    if (!report.baseDir) {
        return nil;
    }
    NSString *descriptorPath = [report.baseDir.path stringByAppendingPathComponent:@"dice.json"];
    NSData *jsonData = [self.fileManager contentsAtPath:descriptorPath];
    if (jsonData == nil || jsonData.length == 0) {
        descriptorPath = [report.baseDir.path stringByAppendingPathComponent:@"metadata.json"];
        jsonData = [self.fileManager contentsAtPath:descriptorPath];
    }
    if (jsonData == nil || jsonData.length == 0) {
        return nil;
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    return json;
}

- (void)filesDidMoveToTrashByDeleteReportProcess:(DICEDeleteReportProcess *)process
{
    // TODO: handle move failure
    dispatch_async(dispatch_get_main_queue(), ^{
        process.report.importStatus = ReportImportStatusDeleted;
        [_reports removeObject:process.report];
        [self.notifications postNotificationName:ReportNotification.reportRemoved object:self userInfo:@{@"report": process.report}];
    });
}

- (void)noFilesFoundToDeleteByDeleteReportProcess:(DICEDeleteReportProcess *)process
{
    [self filesDidMoveToTrashByDeleteReportProcess:process];
}



@end
