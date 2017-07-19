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


@implementation NSArray (ReportTypes)

- (id<ReportType>)reportTypeForId:(NSString *)reportTypeId
{
    for (id<ReportType> type in self) {
        if ([reportTypeId isEqualToString:type .reportTypeId]) {
            return type;
        }
    }
    return nil;
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


@interface ReportImportContext : NSObject 

@property id<DICEArchive> archive;

@end


@implementation ReportImportContext
@end


@interface ReportStore () <UnzipDelegate, DICEDeleteReportProcessDelegate>
@end


@implementation ReportStore
{
    NSMutableArray<ImportProcess *> *_pendingImports;
    DICEDownloadManager *_downloadManager;
    NSURL *_trashDir;
    UIBackgroundTaskIdentifier _importBackgroundTaskId;
    NSMutableDictionary<NSManagedObjectID *, ReportImportContext *> *_transientImportContext;
    dispatch_queue_t _sync;
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

- (instancetype)initWithReportTypes:(NSArray *)reportTypes
    reportsDir:(NSURL *)reportsDir
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

    _sync = dispatch_queue_create("ReportStore-sync", DISPATCH_QUEUE_SERIAL);
    _reportTypes = reportTypes;
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

    // TODO: do in [reportDb performBlock:]
    if (!report.isImportFinished) {
        return;
    }
    report.isEnabled = NO;
    report.importStatus = ReportImportStatusDeleting;
    report.statusMessage = @"Deleting content...";
    DICEDeleteReportProcess *delReport = [[DICEDeleteReportProcess alloc]
        initWithReport:report trashDir:_trashDir preservingMetaData:NO fileManager:self.fileManager];
    delReport.delegate = self;
    dispatch_async(_sync, ^{
        [_pendingImports addObject:delReport]; // retain so it doesn't get deallocated
        [self.importQueue addOperations:delReport.steps waitUntilFinished:NO];
    });
}

- (nullable Report *)reportForUrl:(NSURL *)pathUrl
{
    NSFetchRequest *urlQuery = [Report fetchRequest];
    urlQuery.predicate = [NSCompoundPredicate orPredicateWithSubpredicates:@[
       [NSPredicate predicateWithFormat:@"remoteSourceUrl == %@", pathUrl.absoluteString],
       [NSPredicate predicateWithFormat:@"sourceFileUrl == %@", pathUrl.absoluteString],
       [NSPredicate predicateWithFormat:@"importDirUrl == %@", pathUrl.absoluteString]
    ]];
    __block Report *report;
    [self.reportDb performBlockAndWait:^{
        NSError *error;
        NSArray<Report *> *result = [self.reportDb executeFetchRequest:urlQuery error:&error];
        if (result == nil || error) {
            // TODO: check error
            return;
        }
        if (result.count > 1) {
            // TODO: should not happen
            return;
        }
        report = result.firstObject;
    }];

    return report;
}

- (nullable id<ReportType>)reportTypeForId:(NSString *)reportTypeId
{
    if (reportTypeId == nil) {
        return nil;
    }
    for (id<ReportType> type in self.reportTypes) {
        if ([reportTypeId isEqualToString:type.reportTypeId]) {
            return type;
        }
    }
    return nil;
}

- (void)initializeReport:(Report *)report forSourceUrl:(NSURL *)url
{
    report.contentId = nil;
    report.baseDirName = nil;
    report.dateAdded = [NSDate date];
    report.dateLastAccessed = report.dateAdded;
    report.downloadProgress = 0;
    report.downloadSize = 0;
    report.extractPercent = 0;
    report.importDirUrl = nil;
    report.importStatus = ReportImportStatusNew;
    report.isEnabled = NO;
    report.lat = nil;
    report.lon = nil;
    report.remoteSource = nil;
    report.rootFilePath = nil;
    report.sourceFile = nil;
    report.statusMessage = nil;
    report.summary = nil;
    report.thumbnailPath = nil;
    report.tileThumbnailPath = nil;
    report.title = nil;
    report.uti = nil;

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
        _transientImportContext[report.objectID] = [[ReportImportContext alloc] init];
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
    else if (enteringState == ReportImportStatusExtractingContent) {
        transitionSel = @selector(beginExtractingSourceFileArchiveOfReport:);
    }
    else if (enteringState == ReportImportStatusMovingContent) {
        transitionSel = @selector(beginMovingSourceFileContentOfReport:);
    }
    else if (enteringState == ReportImportStatusDigesting) {
        transitionSel = @selector(beginDigestingContentOfReport:);
    }
    else if (!report.isImportFinished) {
        [NSException raise:NSInternalInconsistencyException format:@"erroneous transition to unknown state %d for report\n%@", enteringState, report];
    }

    NSError *error;
    if (![self.reportDb save:&error]) {
        vlog(@"error saving report before transition from state %d to %d\n%@", leavingState, enteringState, report);
    }
    
    if (report.isImportFinished) {
        [_transientImportContext removeObjectForKey:report.objectID];
        return;
    }
    else if (enteringState != ReportImportStatusNew && enteringState == leavingState) {
        return;
    }

    if (transitionSel == NULL) {
        [NSException raise:NSInternalInconsistencyException
            format:@"no selector for transition from %d to %d for report:\n%@", report.importStatus, enteringState, report];
    }

    IMP transitionImp = [self methodForSelector:transitionSel];
    void (*transition)(id, SEL, Report *) = (void *)transitionImp;
    [self.reportDb performBlock:^{
        transition(self, transitionSel, report);
    }];
}

- (void)beginInspectingNewReport:(Report *)report
{
    ReportImportStatus next;
    if (report.sourceFile) {
        next = ReportImportStatusInspectingSourceFile;
    }
    else if (report.remoteSource) {
        next = ReportImportStatusDownloading;
    }
    else {
        [NSException raise:NSInternalInconsistencyException format:@"report has no source url:\n%@", report];
    }

    [self saveReport:report enteringState:next];
}

- (void)beginInspectingSourceFileForReport:(Report *)report
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // TODO: identify the task name for the report, or just use one task for all pending imports?
        if (_importBackgroundTaskId == UIBackgroundTaskInvalid) {
            _importBackgroundTaskId = [self.application beginBackgroundTaskWithName:@"dice.background_import" expirationHandler:^{
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

    ReportImportStatus next;
    CFStringRef uti = (__bridge CFStringRef)report.uti;
    if ([self.utiExpert uti:uti conformsToUti:kUTTypeZipArchive]) {
        next = ReportImportStatusInspectingArchive;
    }
    else {
        next = ReportImportStatusInspectingContent;
    }

    [self saveReport:report enteringState:next];
}

- (void)beginDownloadingRemoteSourceOfReport:(Report *)report
{
    report.title = @"Downloading...";
    report.statusMessage = [NSString stringWithFormat:@"downloading %@", report.remoteSourceUrl];
    [self saveReport:report enteringState:report.importStatus];
    [self.downloadManager downloadUrl:report.remoteSource];
}

- (void)beginInspectingSourceFileArchiveOfReport:(Report *)report
{
    // get zip file listing on background thread
    // find appropriate report type for archive contents
    CFStringRef uti = (__bridge CFStringRef)report.uti;
    id<DICEArchive> archive = [self.archiveFactory createArchiveForResource:report.sourceFile withUti:uti];
    _transientImportContext[report.objectID].archive = archive;
    InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
        initWithReport:report reportArchive:archive candidateReportTypes:self.reportTypes utiExpert:self.utiExpert];
    __weak InspectReportArchiveOperation *completedOp = op;
    op.completionBlock = ^{
        [self archiveInspectionDidFinish:completedOp];
    };
    [self.importQueue addOperation:op];
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

- (void)beginExtractingSourceFileArchiveOfReport:(Report *)report
{
    id<ReportType> type = [self reportTypeForId:report.reportTypeId];
    ReportImportContext *importContext = _transientImportContext[report.objectID];
    id<DICEArchive> archive = importContext.archive;
    if (archive == nil) {
        archive = [self.archiveFactory createArchiveForResource:report.sourceFile withUti:(__bridge CFStringRef)report.uti];
    }
    vlog(@"extracting report archive %@", report.sourceFile);
    NSURL *extractToDir = report.importDir;
    if (report.baseDirName == nil) {
        report.baseDirName = @"dice_content";
        extractToDir = [extractToDir URLByAppendingPathComponent:report.baseDirName isDirectory:YES];
        NSError *mkdirError;
        if (![self.fileManager createDirectoryAtURL:extractToDir withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
            report.statusMessage = [NSString stringWithFormat:@"Error creating base directory for report %@: %@", report.title, mkdirError.localizedDescription];
            [self saveReport:report enteringState:ReportImportStatusFailed];
        }
    }
    DICEExtractReportOperation *extract = [[DICEExtractReportOperation alloc]
        initWithReport:report reportType:type archive:archive extractToDir:extractToDir fileManager:self.fileManager];
    extract.delegate = self;
    [self.importQueue addOperation:extract];
}

- (void)beginMovingSourceFileContentOfReport:(Report *)report
{
    MoveFileOperation *mv = [[[MoveFileOperation alloc]
        initWithSourceUrl:report.sourceFile destUrl:nil fileManager:self.fileManager] createDestDirs:YES];
    if ([self.fileManager isDirectoryAtUrl:report.sourceFile]) {
        report.baseDirName = report.sourceFile.lastPathComponent;
        mv.destUrl = report.baseDir;
    }
    else {
        report.baseDirName = @"dice_content";
        report.rootFilePath = report.sourceFile.lastPathComponent;
        mv.destUrl = report.rootFile;
    }

    [self saveReport:report enteringState:report.importStatus];

    void (^afterMove)() = ^{
        if (mv.fileWasMoved) {
            [self saveReport:report enteringState:ReportImportStatusDigesting];
        }
        else {
            vlog(@"error moving report source file to import dir of report %@: %@", report, mv.error);
            report.statusMessage = [NSString stringWithFormat:
                @"Error moving source file %@ to import directory: %@",
                report.sourceFile.lastPathComponent, mv.error.localizedDescription];
            [self saveReport:report enteringState:ReportImportStatusFailed];
        }
    };
    mv.completionBlock = ^{
        [self.reportDb performBlock:afterMove];
    };

    [self.importQueue addOperation:mv];
}

- (void)beginDigestingContentOfReport:(Report *)report
{
    vlog(@"creating import process for report %@", report);
    id<ReportType> type = [self reportTypeForId:report.reportTypeId];
    // TODO: farm this out to import queue
    ImportProcess *importProcess = [type createProcessToImportReport:report];
    // TODO: check nil importProcess
    importProcess.delegate = self;
    report.importStatus = ReportImportStatusDigesting;
    report.statusMessage = @"Proccessing content...";
    [self saveReport:report enteringState:report.importStatus];
    vlog(@"queuing import process for report %@", report);
    dispatch_async(_sync, ^{
        // retain the import process so arc does not deallocate it
        [_pendingImports addObject:importProcess];
        [self.importQueue addOperations:importProcess.steps waitUntilFinished:NO];
    });
}

#pragma mark - private methods

- (void)archiveInspectionDidFinish:(InspectReportArchiveOperation *)op
{
    Report *report = op.report;
    id<ReportType> type = op.matchedPredicate.reportType;
    if (type == nil) {
        [self noTypeFoundForReport:report];
    }
    else {
        [self prepareReport:report toImportAsType:type toBaseDirNamed:op.archiveBaseDir enteringNextState:ReportImportStatusExtractingContent];
    }
}

- (void)contentInspectionDidFinish:(MatchReportTypeToContentAtPathOperation *)op
{
    Report *report = op.report;
    id<ReportType> type = op.matchedReportType;
    if (type == nil) {
        [self noTypeFoundForReport:report];
    }
    else {
        [self prepareReport:report toImportAsType:type toBaseDirNamed:nil enteringNextState:ReportImportStatusMovingContent];
    }
}

- (void)prepareReport:(Report *)report toImportAsType:(id<ReportType>)type toBaseDirNamed:(NSString *)baseDirName enteringNextState:(ReportImportStatus)nextState
{
    [self.reportDb performBlock:^{
        report.reportTypeId = type.reportTypeId;
        NSString *importDirName = [report.sourceFile.lastPathComponent stringByAppendingString:ImportDirSuffix];
        report.importDir = [self.reportsDir URLByAppendingPathComponent:importDirName isDirectory:YES];
        report.baseDirName = baseDirName;
        [self saveReport:report enteringState:nextState];
        [self makeImportDirForReport:report];
    }];
}

- (void)noTypeFoundForReport:(Report *)report
{
    [self.reportDb performBlock:^{
        vlog(@"no report type found for report %@", report.sourceFile);
        report.statusMessage = @"Unknown content type";
        [self saveReport:report enteringState:ReportImportStatusFailed];
    }];
}

- (void)makeImportDirForReport:(Report *)report;
{
    NSError *error = nil;
    if ([self.fileManager fileExistsAtPath:report.importDir.path]) {
        // TODO: prompt to make new report or overwrite existing
        vlog(@"import dir already exists for report:\n%@", report);
        return;
    }
    BOOL created = [self.fileManager createDirectoryAtURL:report.importDir withIntermediateDirectories:YES attributes:nil error:&error];
    if (!created) {
        vlog(@"error creating import dir for report:%@\n%@", error, report)
        // TODO: coping with failure
    }
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
        // TODO: core data delete from persistent store
        // TODO: what if it failed?
        // TODO: worry about background task? we didn't begin one for this import process
        dispatch_sync(_sync, ^{
            [_pendingImports removeObject:importProcess];
        });
        return;
    }

    [self.reportDb performBlock:^{
        vlog(@"import did finish for report %@", importProcess.report);
        NSDictionary *descriptor = [self parseJsonDescriptorIfAvailableForReport:importProcess.report];
        Report *report = importProcess.report;
        if (importProcess.wasSuccessful) {
            if (descriptor) {
                [report setPropertiesFromJsonDescriptor:descriptor];
            }
            // TODO: check rootFile uti
            vlog(@"enabling report %@", report);
            report.isEnabled = YES;
            report.statusMessage = @"Import complete";
            [self saveReport:report enteringState:ReportImportStatusSuccess];
        }
        else {
            vlog(@"disabling report %@ after unsuccessful import", report);
            report.isEnabled = NO;
            report.statusMessage = @"Failed to import content";
            [self saveReport:report enteringState:ReportImportStatusFailed];
        }
        [self clearPendingImport:importProcess];
    }];
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

- (void)unzipOperation:(UnzipOperation *)op didUpdatePercentComplete:(NSUInteger)percent
{
    assert(false);
//    dispatch_async(dispatch_get_main_queue(), ^{
//        Report *report = [self reportForUrl:op.archive.archiveUrl];
//        report.summary = [NSString stringWithFormat:@"Extracting - %@%%", @(percent)];
//    });
}

- (void)unzipOperationDidFinish:(UnzipOperation *)op
{
    assert(false);
//    DICEExtractReportOperation *extract = (DICEExtractReportOperation *)op;
//    BOOL success = op.wasSuccessful;
//    Report *report = extract.report;
//    id<ReportType> reportType = extract.reportType;
//    NSURL *baseDir = extract.extractedReportBaseDir;
//
//    vlog(@"finished extracting contents of report archive %@", report);
//
//    if (!success) {
//        NSLog(@"extraction of archive %@ was not successful", report.sourceFile);
//        dispatch_async(dispatch_get_main_queue(), ^{
//            report.summary = report.statusMessage = @"Failed to extract archive contents";
//            report.importStatus = ReportImportStatusFailed;
//            [self finishBackgroundTaskIfImportsFinished];
//        });
//        return;
//    }
//
//    NSBlockOperation *createImportProcess = [NSBlockOperation blockOperationWithBlock:^{
//        [self importReport:report asReportType:reportType];
//    }];
//    DeleteFileOperation *deleteArchive = [[DeleteFileOperation alloc] initWithFileUrl:extract.archive.archiveUrl fileManager:self.fileManager];
//
//    dispatch_async(dispatch_get_main_queue(), ^{
//        report.baseDir = baseDir;
//        [self.importQueue addOperation:createImportProcess];
//        [self.importQueue addOperation:deleteArchive];
//    });
}

#pragma mark - background handling

- (void)clearPendingImport:(ImportProcess *)importProcess
{
    dispatch_sync(_sync, ^{
        vlog(@"clearing pending import for report %@, pending imports remainging %lu", importProcess.report, (unsigned long) _pendingImports.count);
        NSUInteger pos = [_pendingImports indexOfObject:importProcess];
        if (pos == NSNotFound) {
            if (_importBackgroundTaskId != UIBackgroundTaskInvalid) {
                [NSException raise:NSInternalInconsistencyException format:
                    @"attempt to remove pending import process for report %@, but there was no such process", importProcess.report];
            }
        }
        else {
            [_pendingImports removeObjectAtIndex:pos];
        }
    });

    [self finishBackgroundTaskIfImportsFinished];
}

- (void)suspendAndClearPendingImports
{
    self.importQueue.suspended = YES;
    
    dispatch_sync(_sync, ^{
        for (ImportProcess *importProcess in _pendingImports) {
            [importProcess cancel];
        }
        [_pendingImports removeAllObjects];

        // TODO: core data fetch
        //    for (Report *report in _reports) {
        //        if (!report.isReadyForShutdown) {
        //            report.importStatus = ReportImportStatusFailed;
        //        }
        //    }

        NSArray<NSOperation *> *ops = self.importQueue.operations;
        [self.importQueue cancelAllOperations];
        for (NSOperation *op in ops) {
            if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                DICEExtractReportOperation *extract = (DICEExtractReportOperation *)op;
                // TODO: save extract progress instead of removing extracted content
                // TODO: move to trash instead of deleting
                // TODO: move to background thread
                BOOL removed = [self.fileManager removeItemAtURL:extract.report.baseDir error:NULL];
                if (!removed) {
                    // TODO: something
                }
            }
        }
    });

    [self endBackgroundTask];
}

- (void)finishBackgroundTaskIfImportsFinished
{
    NSPredicate *pendingReportsPredicate = [NSPredicate predicateWithFormat:@"NOT(importStatus IN %@)",
        @[@(ReportImportStatusDownloading), @(ReportImportStatusSuccess), @(ReportImportStatusFailed)]];
    NSFetchRequest *fetchPendingReports = [Report fetchRequest];
    fetchPendingReports.predicate = pendingReportsPredicate;

    dispatch_sync(_sync, ^{
        __block NSError *error;
        __block NSUInteger pendingReportCount;
        [self.reportDb performBlockAndWait:^{
            pendingReportCount = [self.reportDb countForFetchRequest:fetchPendingReports error:&error];
        }];
        if (error || pendingReportCount == NSNotFound) {
            vlog(@"error counting pending reports: %@", error);
            return;
        }
        if (pendingReportCount) {
            return;
        }
        if (_pendingImports.count == 0) {
            [self endBackgroundTask];
        }
    });
}

- (void)endBackgroundTask
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_importBackgroundTaskId == UIBackgroundTaskInvalid) {
            [NSException raise:NSInternalInconsistencyException
                format:@"multiple attempts to end the background task - no pending imports remain but background task id is invalid"];
        }
        vlog(@"ending background task %lu", (unsigned long) _importBackgroundTaskId);
        [self.application endBackgroundTask:_importBackgroundTaskId];
        _importBackgroundTaskId = UIBackgroundTaskInvalid;
    });
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
