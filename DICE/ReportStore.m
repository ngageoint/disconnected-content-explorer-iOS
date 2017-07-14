//
//  ReportStore.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import <MagicalRecord/MagicalRecord.h>

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
#import "NSFileManager+Convenience.h"
#import "NSURL+ResourceValues.h"


void ensureMainThread() {
    if (!NSThread.isMainThread) {
        [NSException raise:NSInternalInconsistencyException format:@"expected main thread"];
    }
}


@implementation Report (ReportStoreDRY)

- (BOOL)isReadyForShutdown
{
    return self.isImportFinished || self.importStatus == ReportImportStatusDownloading;
}

@end


/*
 The import state machine:

 new                -> readyToInspect|downloading
 readyToInspect     -> inspectingArchive|inspectingContent
 inspectingContent  -> readyToImport|failed(inspection)
 readyToImport      -> importing
 importing          -> success|failed(import)
 inspectingArchive  -> extracting|failed(inspection)
 extracting         -> readyToImport|failed(extraction)
 downloading        -> readyToInspect|failed(download)

 all states:
 0: new
 1: readyToInspect
 2: inspectingArchive
 3: extracting
 4: inspectingContent
 5: readyToImport
 6: importing
 7: downloading
 8: success
 9: failed
 */

@protocol StateTransition <NSObject>

- (NSNumber *)from;
- (NSNumber *)to;
- (BOOL)perform;
- (NSError *)error;

@end


static NSString *const ImportDirSuffix = @".dice_import";


@interface ReportImportContext

@property id<ReportType> type;
@property id<DICEArchive> archive;
@property NSString *baseDirInArchive;

@end


@implementation NSDictionary (ReportImportContext)

@end


@interface ReportStore () <UnzipDelegate, DICEDeleteReportProcessDelegate>
@end


@implementation ReportStore
{
    NSMutableArray<Report *> *_reports;
    NSMutableArray<ImportProcess *> *_pendingImports;
    DICEDownloadManager *_downloadManager;
    NSURL *_trashDir;
    UIBackgroundTaskIdentifier _importBackgroundTaskId;
    BOOL _backgroundTimeExpired;
    NSDictionary<NSManagedObjectID *, ReportImportContext *> *_transientImportContext;
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
    return _sharedInstance;
}

- (instancetype)init
{
    [NSException raise:NSGenericException format:@"cannot call default init on %@", self.class];
    return nil;
}

- (instancetype)initWithReportsDir:(NSURL *)reportsDir
    exclusions:(NSArray *)exclusions
    utiExpert:(DICEUtiExpert *)utiExpert
    archiveFactory:(id<DICEArchiveFactory>)archiveFactory
    importQueue:(NSOperationQueue *)importQueue
    fileManager:(NSFileManager *)fileManager
    reportDb:(NSManagedObjectContext *)reportDb
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
    _reportDb = reportDb;
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

    // TODO: handle errors more goodly
    NSError *err;
    BOOL created = [_fileManager createDirectoryAtURL:_trashDir withIntermediateDirectories:YES attributes:nil error:&err];
    if (!created) {
        [NSException raise:NSInternalInconsistencyException format:@"error creating trash directory %@: %@", _trashDir, err.localizedDescription];
    }

    return self;
}

#pragma mark - public api

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

- (void)loadContentFromReportsDir
{
    ensureMainThread();
    
    NSIndexSet *defunctReports = [_reports indexesOfObjectsPassingTest:^BOOL(Report *report, NSUInteger idx, BOOL *stop) {
        if (report.importStatus == ReportImportStatusSuccess && ![self.fileManager isDirectoryAtUrl:report.importDir]) {
            return YES;
        }
        return NO;
    }];
    if (defunctReports.count > 0) {
        [_reports removeObjectsAtIndexes:defunctReports];
    }

    NSArray *files = [self.fileManager contentsOfDirectoryAtURL:self.reportsDir includingPropertiesForKeys:@[NSURLFileResourceTypeKey] options:0 error:nil];
    for (NSURL *file in files) {
        vlog(@"attempting to add report from file %@", file);
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
}

- (void)attemptToImportReportFromResource:(NSURL *)reportUrl
{
    ensureMainThread();

    // TODO: this should not be necessary has any import dir should be associated with a persisted record, so reportForUrl should handle it
    if ([reportUrl.lastPathComponent hasSuffix:ImportDirSuffix]) {
        return;
    }

    // TODO: differentiate between new and imported reports (*.dice_import/)
    // here or in loadReports? probably here
    if ([self.reportsDirExclusions evaluateWithObject:reportUrl]) {
        return;
    }

    // TODO: assumes reportUrl is in docs directory
    // TODO: check if this report might have been imported before, e.g., from this same url or perhaps a hash, then prompt to overwrite
    Report *report = [self reportForUrl:reportUrl];
    if (report) {
        return;
    }

    [self.reportDb performBlock:^{
        Report *report = [Report MR_createEntityInContext:self.reportDb];
        [self initializeReport:report forSourceUrl:reportUrl];
        [self saveReport:report enteringState:ReportImportStatusNew];
    }];
}

- (void)retryImportingReport:(Report *)report
{
    ensureMainThread();

    if (!report.isImportFinished) {
        return;
    }

    if (report.remoteSource) {
        [self clearAndRetryDownloadForReport:report];
    }
}

- (Report *)reportForContentId:(NSString *)contentId
{
    // TODO: query by contentId
    return nil;
}

- (void)deleteReport:(Report *)report
{
    ensureMainThread();

    if (!report.isImportFinished) {
        return;
    }
    report.isEnabled = NO;
    report.importStatus = ReportImportStatusDeleting;
    report.statusMessage = @"Deleting content...";
    DICEDeleteReportProcess *delReport = [[DICEDeleteReportProcess alloc]
        initWithReport:report trashDir:_trashDir preservingMetaData:NO fileManager:self.fileManager];
    delReport.delegate = self;
    [_pendingImports addObject:delReport]; // retain so it doesn't get deallocated
    [self.importQueue addOperations:delReport.steps waitUntilFinished:NO];
}

- (void)reportDbDidSave:(NSNotification *)note
{

}

- (void)reportDbWillSave:(NSNotification *)note
{
    NSSet<NSManagedObject *> *updates = self.reportDb.updatedObjects;
    for (Report *report in updates) {
        NSNumber *oldState = report.changedValues[@"importStatus"];
        if (oldState) {
            // verify valid state transition
            ReportImportStatus oldStateInt = (int16_t)oldState.intValue;
            //            [self enterStateOfReport:report leavingState:oldState];
        }
    }
}

- (nullable Report *)reportForUrl:(NSURL *)pathUrl
{
    // TODO: check pathUrl child of reportsDir, return fail Report if not

    NSCompoundPredicate *urlPredicateTemplate = [[NSCompoundPredicate alloc] initWithType:NSOrPredicateType subpredicates:@[
        [NSPredicate predicateWithFormat:@"remoteSourceUrl == $URL"],
        [NSPredicate predicateWithFormat:@"sourceFileUrl == $URL"],
        [NSPredicate predicateWithFormat:@"importDirUrl == $URL"]
    ]];

    NSError *error;
    NSFetchRequest *urlQuery = [NSFetchRequest fetchRequestWithEntityName:@"Report"];
    urlQuery.predicate = [urlPredicateTemplate predicateWithSubstitutionVariables:@{@"URL": pathUrl.absoluteString}];
    NSArray<Report *> *result = [self.reportDb executeFetchRequest:urlQuery error:&error];
    if (result == nil || error) {
        // TODO: check error
    }
    if (result.count > 1) {
        // TODO: should not happen
    }

    return result.firstObject;
}

- (void)initializeReport:(Report *)report forSourceUrl:(NSURL *)url
{
    report.sourceFile = nil;
    report.remoteSource = nil;
    report.baseDir = nil;
    report.rootFile = nil;
    report.uti = nil;
    report.importStatus = ReportImportStatusNew;
    report.downloadProgress = 0;
    report.downloadSize = 0;
    report.isEnabled = NO;
    report.lat = nil;
    report.lon = nil;
    report.contentId = nil;
    report.statusMessage = nil;
    report.summary = nil;
    report.thumbnailPath = nil;
    report.tileThumbnailPath = nil;
    report.title = nil;

    if ([url.scheme.lowercaseString hasPrefix:@"http"]) {
        report.remoteSource = url;
    }
    else if (url.isFileURL) {
        report.sourceFile = url;
    }
}

#pragma mark - state transition methods

- (void)saveReport:(Report *)report enteringState:(ReportImportStatus)enteringState
{
    ReportImportStatus leavingState = report.importStatus;
    report.importStatus = enteringState;

    SEL transitionSel = NULL;

    if (enteringState ==  ReportImportStatusNew) {
        transitionSel = @selector(beginInspectingNewReport:);
    }
    else if (enteringState == ReportImportStatusInspectingSourceFile) {
        transitionSel = @selector(beginInspectingSourceFileForReport:);
    }
    else if (enteringState == ReportImportStatusDownloading) {
        transitionSel = @selector(beginDownloadingRemoteSourceOfReport:);
    }
    else if (enteringState == ReportImportStatusInspectingContent) {
        transitionSel = @selector(beginInspectingSourceFileContentOfReport:);
    }
    else if (enteringState == ReportImportStatusInspectingArchive) {
        transitionSel = @selector(beginInspectingSourceFileArchiveOfReport:);
    }
    else if (enteringState != ReportImportStatusNew || enteringState != ReportImportStatusFailed) {
        [NSException raise:NSInternalInconsistencyException format:@"erroneous transition to unknown state %d for report\n%@", enteringState, report];
    }

    NSError *error;
    if (![self.reportDb save:&error]) {
        vlog(@"error saving report before transition from state %d to %d\n%@", leavingState, enteringState, report);
    }
    if (enteringState == ReportImportStatusFailed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishBackgroundTaskIfImportsFinished];
        });
        return;
    }
    else if (enteringState == leavingState) {
        return;
    }

    IMP transitionImp = [self methodForSelector:transitionSel];
    void (*transition)(id, SEL, Report *) = (void *)transitionImp;
    [self.reportDb performBlock:^{
        transition(self, transitionSel, report);
    }];
}

- (void)beginInspectingNewReport:(Report *)report
{
    if (report.sourceFile) {
        [self saveReport:report enteringState:ReportImportStatusInspectingSourceFile];
    }
    else if (report.remoteSource) {
        [self saveReport:report enteringState:ReportImportStatusDownloading];
    }

    [NSException raise:NSInternalInconsistencyException format:@"report has no source url:\n%@", report];
}

- (void)beginInspectingSourceFileForReport:(Report *)report
{
    if (report.importStatus != ReportImportStatusInspectingSourceFile) {
        [NSException raise:NSInternalInconsistencyException format:@"invalid report state: %d", report.importStatus];
    }

    dispatch_sync(dispatch_get_main_queue(), ^{
        // TODO: identify the task name for the report, or just use one task for all pending imports?
        if (_importBackgroundTaskId == UIBackgroundTaskInvalid) {
            _importBackgroundTaskId = [self.application beginBackgroundTaskWithName:@"dice.background_import" expirationHandler:^{
                _backgroundTimeExpired = YES;
                [self suspendAndClearPendingImports];
            }];
        }
    });

    report.statusMessage = @"Inspecting new content";
    report.title = report.sourceFile.lastPathComponent;

    if (report.uti == nil || [self.utiExpert isDynamicUti:(__bridge CFStringRef)report.uti]) {
        CFStringRef uti = [self.utiExpert preferredUtiForExtension:report.sourceFile.pathExtension conformingToUti:NULL];
        if (uti && ![self.utiExpert isDynamicUti:uti]) {
            report.uti = (__bridge NSString *)uti;
        }
        else {
            report.uti = nil;
        }
    }

    CFStringRef uti = (__bridge CFStringRef)report.uti;
    if ([self.utiExpert uti:uti conformsToUti:kUTTypeZipArchive]) {
        [self saveReport:report enteringState:ReportImportStatusInspectingArchive];
    }
    else {
        [self saveReport:report enteringState:ReportImportStatusInspectingContent];
    }
}

- (void)beginDownloadingRemoteSourceOfReport:(Report *)report
{
    report.title = report.statusMessage = @"Downloading...";
    report.summary = report.remoteSourceUrl;
    [self saveReport:report enteringState:report.importStatus];
    [self.downloadManager downloadUrl:report.remoteSource];
}

- (void)beginInspectingSourceFileArchiveOfReport:(Report *)report
{
    // get zip file listing on background thread
    // find appropriate report type for archive contents
    CFStringRef uti = (__bridge CFStringRef)report.uti;
    id<DICEArchive> archive = [self.archiveFactory createArchiveForResource:report.sourceFile withUti:uti];
    InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
        initWithReport:report reportArchive:archive candidateReportTypes:self.reportTypes utiExpert:self.utiExpert];
    __weak InspectReportArchiveOperation *completedOp = op;
    op.completionBlock = ^{
        [self archiveInspectionDidFinish:completedOp];
    };
    [self.importQueue addOperation:op];
}

- (void)beginExtractingSourceFileArchiveOfReport:(Report *)report
{
    ReportImportContext *importContext = _transientImportContext[report.objectID];
    id<ReportType> type = importContext.type;
    id<DICEArchive> archive = importContext.archive;
    NSString *baseDir = importContext.baseDirInArchive;
    [self extractReportArchive:archive baseDirInArchive:baseDir forReport:report ofType:type];
}

- (void)beginInspectingSourceFileContentOfReport:(Report *)report
{
    // TODO: incorporate report uti here as well
    MatchReportTypeToContentAtPathOperation *op =
    [[MatchReportTypeToContentAtPathOperation alloc] initWithReport:report candidateTypes:self.reportTypes];
    __weak MatchReportTypeToContentAtPathOperation *completedOp = op;
    op.completionBlock = ^{
        [self contentInspectionDidFinish:completedOp];
    };
    [self.importQueue addOperation:op];
}

- (void)beginImportingReport:(Report *)report
{

}

#pragma mark - private methods

- (void)archiveInspectionDidFinish:(InspectReportArchiveOperation *)op
{
    Report *report = op.report;
    id<ReportType> type = op.matchedPredicate.reportType;
    if (type == nil) {
        [self noTypeFoundForReport:report];
        return;
    }
    [self.reportDb performBlock:^{
        vlog(@"matched report type %@ to report archive %@", type, report);
        [self makeImportDirForReport:report];
        [self saveReport:report enteringState:ReportImportStatusExtracting];
    }];
}

- (void)contentInspectionDidFinish:(MatchReportTypeToContentAtPathOperation *)op
{
    Report *report = op.report;
    id<ReportType> type = op.matchedReportType;
    if (type == nil) {
        [self noTypeFoundForReport:report];
        return;
    }
    [self.reportDb performBlock:^{
        vlog(@"matched report type %@ to report %@", type, report);
        [self makeImportDirForReport:report];
        [self moveSourceFileToImportDirOfReport:report importAsType:type];
        [self saveReport:report enteringState:ReportImportStatusImporting];
    }];
}

- (void)noTypeFoundForReport:(Report *)report
{
    [self.reportDb performBlock:^{
        vlog(@"no report type found for report %@", report.sourceFile);
        report.statusMessage = @"Unknown content type";
    }];
}

- (void)makeImportDirForReport:(Report *)report;
{
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

    [self saveReport:report enteringState:report.importStatus];

    __weak MoveFileOperation *completedMove = mv;
    mv.completionBlock = ^{
        if (completedMove.fileWasMoved) {
            [self importReport:report asReportType:reportType];
            return;
        }
        [self.reportDb performBlock:^{
            vlog(@"error moving report source file to import dir of report %@: %@", report, completedMove.error);
            report.importStatus = ReportImportStatusFailed;
            report.statusMessage = [NSString stringWithFormat:
                @"Error moving source file %@ to import directory: %@",
                report.sourceFile.lastPathComponent, completedMove.error.localizedDescription];
            NSError *error;
            if (![self.reportDb save:&error]) {
                vlog(@"error saving report record after failed move to import dir: %@\n%@", error, report);
            }
        }];
    };;
    [self.importQueue addOperation:mv];
}

- (void)importReport:(Report *)report asReportType:(id<ReportType>)type
{
    vlog(@"creating import process for report %@", report);
    ImportProcess *importProcess = [type createProcessToImportReport:report toDir:self.reportsDir];
    // TODO: check nil importProcess
    importProcess.delegate = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"queuing import process for report %@", report);
        [_pendingImports addObject:importProcess];
        report.importStatus = ReportImportStatusImporting;
        report.summary = report.statusMessage = @"Importing content...";
        [self.importQueue addOperations:importProcess.steps waitUntilFinished:NO];
    });
}

#pragma mark - import delegate methods

- (void)reportWasUpdatedByImportProcess:(ImportProcess *)import
{
    // TODO: persist
}

- (void)importDidFinishForImportProcess:(ImportProcess *)importProcess
{
    if ([importProcess isKindOfClass:[DICEDeleteReportProcess class]]) {
        vlog(@"delete process finished for report %@", importProcess.report);
        // TODO: what if it failed?
        // TODO: worry about background task? we didn't begin one for this import process
        [_pendingImports removeObject:importProcess];
        return;
    }
    vlog(@"import did finish for report %@", importProcess.report);
    NSDictionary *descriptor = [self parseJsonDescriptorIfAvailableForReport:importProcess.report];
    // TODO: assign contentId if nil
    dispatch_async(dispatch_get_main_queue(), ^{
        // TODO: leave failed imports so user can decide what to do, retry, delete, etc?
        vlog(@"finalizing import for report %@", importProcess.report);
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
            // TODO: check rootFile uti
            vlog(@"enabling report %@", report);
            report.isEnabled = YES;
            report.importStatus = ReportImportStatusSuccess;
            report.statusMessage = @"Import complete";
        }
        else {
            vlog(@"disabling report %@ after unsuccessful import", report);
            report.isEnabled = NO;
            report.importStatus = ReportImportStatusFailed;
            report.summary = report.statusMessage = @"Failed to import content";
        }
        [self clearPendingImport:importProcess];
    });
}

#pragma mark - download delegate methods

- (void)downloadManager:(DICEDownloadManager *)downloadManager didReceiveDataForDownload:(DICEDownload *)download
{
    ensureMainThread();

    Report *report = [self reportForDownload:download];
    if (download.percentComplete == report.downloadProgress) {
        return;
    }
    report.title = [NSString stringWithFormat:@"Downloading... %li%%", (long)download.percentComplete];
    report.downloadProgress = (NSUInteger) download.percentComplete;
}

- (NSURL *)downloadManager:(DICEDownloadManager *)downloadManager willFinishDownload:(DICEDownload *)download movingToFile:(NSURL *)destFile
{
    ensureMainThread();

    Report *report = [self reportForDownload:download];
    report.sourceFile = destFile;
    return nil;
}

- (void)downloadManager:(DICEDownloadManager *)downloadManager didFinishDownload:(DICEDownload *)download
{
    assert(false);

    if (downloadManager.isFinishingBackgroundEvents) {
        // the app was launched into the background to finish background downloads, so defer expensive
        // import of downloaded files until the user next launches the application
        return;
    }

    Report *report = [self reportForDownload:download];

    if (!download.wasSuccessful || download.downloadedFile == nil) {
        // TODO: mechanism to retry
        report.title = @"Download failed";
        report.importStatus = ReportImportStatusFailed;
        report.statusMessage = download.error.localizedDescription;
        report.isEnabled = NO;
        return;
    }

    report.title = download.downloadedFile.lastPathComponent;
    report.importStatus = ReportImportStatusInspectingSourceFile;
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
    [self beginInspectingSourceFileForReport:report];
}

/**
 * Retrieve the report record for the given download.
 * @param download
 * @return
 */
- (Report *)reportForDownload:(DICEDownload *)download
{
    ensureMainThread();

    Report *report = [self reportForUrl:download.url];
    if (report) {
        return report;
    }
    // TODO: cancel download?
    vlog(@"no record for download @ url %@", download.url);
    return nil;
}

- (void)clearAndRetryDownloadForReport:(Report *)report
{
    assert(false);
//    ensureMainThread();
//
//    report.isEnabled = NO;
//    report.importStatus = ReportImportStatusNewRemote;
//    report.title = report.statusMessage = @"Retrying download";
//    report.summary = report.remoteSource.absoluteString;
//    // TODO: leave import dir and persisted record? option on DICEDeleteReportProcess? maybe just manually delete base dir and source file?
//    DICEDeleteReportProcess *startFresh = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:_trashDir preservingMetaData:YES fileManager:self.fileManager];
//    [_pendingImports addObject:startFresh];
//    startFresh.delegate = self;
//    [self.importQueue addOperations:startFresh.steps waitUntilFinished:NO];
}

#pragma mark - archives

/**
 * invoke on main thread
 */
- (void)extractReportArchive:(id<DICEArchive>)archive baseDirInArchive:(NSString *)baseDir forReport:(Report *)report ofType:(id<ReportType>)reportType
{
    ensureMainThread();

    vlog(@"extracting report archive %@", report.sourceFile);
    NSURL *extractToDir = report.importDir;
    if (baseDir == nil) {
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
    [self.importQueue addOperation:extract];
}

- (void)unzipOperation:(UnzipOperation *)op didUpdatePercentComplete:(NSUInteger)percent
{
    dispatch_async(dispatch_get_main_queue(), ^{
        Report *report = [self reportForUrl:op.archive.archiveUrl];
        report.summary = [NSString stringWithFormat:@"Extracting - %@%%", @(percent)];
    });
}

- (void)unzipOperationDidFinish:(UnzipOperation *)op
{
    DICEExtractReportOperation *extract = (DICEExtractReportOperation *)op;
    BOOL success = op.wasSuccessful;
    Report *report = extract.report;
    id<ReportType> reportType = extract.reportType;
    NSURL *baseDir = extract.extractedReportBaseDir;

    vlog(@"finished extracting contents of report archive %@", report);

    if (!success) {
        NSLog(@"extraction of archive %@ was not successful", report.sourceFile);
        dispatch_async(dispatch_get_main_queue(), ^{
            report.summary = report.statusMessage = @"Failed to extract archive contents";
            report.importStatus = ReportImportStatusFailed;
            [self finishBackgroundTaskIfImportsFinished];
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

#pragma mark - background handling

- (void)clearPendingImport:(ImportProcess *)importProcess
{
    ensureMainThread();

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
    ensureMainThread();

    self.importQueue.suspended = YES;

    for (ImportProcess *importProcess in _pendingImports) {
        [importProcess cancel];
    }
    [_pendingImports removeAllObjects];

    // TODO: core data fetch
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
    ensureMainThread();

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
    ensureMainThread();

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

#pragma mark - deleting

- (void)filesDidMoveToTrashByDeleteReportProcess:(DICEDeleteReportProcess *)process
{
    // TODO: handle move failure
    assert(false);
//    dispatch_async(dispatch_get_main_queue(), ^{
//        Report *report = process.report;
//        if (report.importStatus == ReportImportStatusNewRemote) {
//            // it's a retry
//            [self initializeReport:report forSourceUrl:report.remoteSource];
//            [self beginImportingNewReport:report];
//        }
//        else {
//            process.report.importStatus = ReportImportStatusDeleted;
//            [_reports removeObject:process.report];
//        }
//    });
}

- (void)noFilesFoundToDeleteByDeleteReportProcess:(DICEDeleteReportProcess *)process
{
    [self filesDidMoveToTrashByDeleteReportProcess:process];
}



@end
