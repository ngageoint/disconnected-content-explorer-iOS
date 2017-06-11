#import "Report.h"
#import "Specta.h"
#import "SpectaUtility.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <JGMethodSwizzler/JGMethodSwizzler.h>

#import "DICEArchive.h"
#import "DICEExtractReportOperation.h"
#import "FileOperations.h"
#import "ImportProcess+Internal.h"
#import "NotificationRecordingObserver.h"
#import "NSOperation+Blockable.h"
#import "NSString+PathUtils.h"
#import "ReportStore.h"
#import "ReportType.h"
#import "TestDICEArchive.h"
#import "TestOperationQueue.h"
#import "TestReportType.h"
#import "DICEUtiExpert.h"
#import "MatchReportTypeToContentAtPathOperation.h"
#import "TestFileManager.h"
#import <stdatomic.h>



/**
 This category enables the OCHamcrest endsWith matcher to accept
 NSURL objects.
 */
@interface NSURL (HasSuffixSupport)

- (BOOL)hasSuffix:(NSString *)suffix;

@end

@implementation NSURL (HasSuffixSupport)

- (BOOL)hasSuffix:(NSString *)suffix
{
    return [self.path hasSuffix:suffix];
}

@end


SpecBegin(ReportStore)



xdescribe(@"NSFileManager", ^{

    it(@"returns directory url with trailing slash", ^{
        NSURL *resources = [[[NSBundle bundleForClass:[self class]] bundleURL] URLByAppendingPathComponent:@"etc" isDirectory:YES];
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:resources includingPropertiesForKeys:nil options:0 error:NULL];
        NSURL *dirUrl;
        for (NSURL *url in contents) {
            if ([url.lastPathComponent isEqualToString:@"a_directory"]) {
                dirUrl = url;
            }
        }

        expect([dirUrl.absoluteString hasSuffix:@"/"]).to.equal(YES);
        expect([dirUrl.path hasSuffix:@"/"]).to.equal(NO);

        NSString *resourceType;
        [dirUrl getResourceValue:&resourceType forKey:NSURLFileResourceTypeKey error:NULL];
        expect(resourceType).to.equal(NSURLFileResourceTypeDirectory);
    });

});

describe(@"ReportStore", ^{

    __block TestReportType *redType;
    __block TestReportType *blueType;
    __block TestFileManager *fileManager;
    __block id<DICEArchiveFactory> archiveFactory;
    __block DICEDownloadManager *downloadManager;
    __block TestOperationQueue *importQueue;
    __block NSNotificationCenter *notifications;
    __block ReportStore *store;
    __block UIApplication *app;
    __block NSUInteger backgroundTaskId;
    __block void (^backgroundTaskHandler)(void);
    __block NSURL *reportsDir;

    beforeAll(^{
    });

    beforeEach(^{
        NSString *testNameComponent = ((SPTSpec *)SPTCurrentSpec).name;
        NSRange doubleUnderscore = [testNameComponent rangeOfString:@"__" options:NSBackwardsSearch];
        testNameComponent = [testNameComponent substringFromIndex:doubleUnderscore.location + 2];
        NSRegularExpression *nonWords = [NSRegularExpression regularExpressionWithPattern:@"\\W" options:0 error:NULL];
        testNameComponent = [nonWords stringByReplacingMatchesInString:testNameComponent options:0 range:NSMakeRange(0, testNameComponent.length) withTemplate:@""];
        NSString *reportsDirPath = [NSString stringWithFormat:@"/%@/reports/", testNameComponent];
        reportsDir = [NSURL fileURLWithPath:reportsDirPath];
        fileManager = [[[TestFileManager alloc] init] createPaths:reportsDirPath, nil];
        fileManager.workingDir = reportsDir.path;
        archiveFactory = mockProtocol(@protocol(DICEArchiveFactory));
        downloadManager = mock([DICEDownloadManager class]);
        importQueue = [[TestOperationQueue alloc] init];
        notifications = [[NSNotificationCenter alloc] init];
        app = mock([UIApplication class]);
        backgroundTaskId = 0;
        backgroundTaskHandler = nil;
        [given([app beginBackgroundTaskWithName:@"dice.background_import" expirationHandler:anything()]) willDo:^id(NSInvocation *invocation) {
            if (backgroundTaskHandler != nil) {
                failure(@"attempted to begin background task with non-nil background task handler");
                return @(UIBackgroundTaskInvalid);
            }
            backgroundTaskHandler = invocation.mkt_arguments[1];
            backgroundTaskId += 1;
            return @(backgroundTaskId);
        }];
        [[givenVoid([app endBackgroundTask:0]) withMatcher:anything()] willDo:^id(NSInvocation *invocation) {
            NSUInteger endingTaskId = ((NSNumber *)invocation.mkt_arguments[0]).unsignedIntegerValue;
            if (endingTaskId != backgroundTaskId) {
                failure([NSString stringWithFormat:@"attempted to end background task with id %lu but outstanding task id was %lu", endingTaskId, backgroundTaskId]);
            }
            if (backgroundTaskHandler == nil) {
                failure([NSString stringWithFormat:@"attempted to end background task id %lu but handler is nil", backgroundTaskId]);
            }
            backgroundTaskHandler = nil;
            return nil;
        }];

        redType = [[TestReportType alloc] initWithExtension:@"red" fileManager:fileManager];
        blueType = [[TestReportType alloc] initWithExtension:@"blue" fileManager:fileManager];

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir
            exclusions:nil
            utiExpert:[[DICEUtiExpert alloc] init]
            archiveFactory:archiveFactory
            importQueue:importQueue
            fileManager:fileManager
            notifications:notifications
            application:app];
        store.downloadManager = downloadManager;

        store.reportTypes = @[
            redType,
            blueType
        ];
    });

    afterEach(^{
        [importQueue waitUntilAllOperationsAreFinished];
        stopMocking(archiveFactory);
        stopMocking(app);
        fileManager = nil;
    });

    afterAll(^{
        
    });

    xdescribe(@"load all reports", ^{

        beforeEach(^{
        });

        it(@"creates reports for each file in reports directory", ^{

            [fileManager createPaths:@"report1.red", @"report2.blue", @"something.else", nil];

            id redImport = [redType enqueueImport];
            id blueImport = [blueType enqueueImport];

            NSArray *reports = [store loadReports];

            expect(reports.count).to.equal(3);
            expect(((Report *)reports[0]).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(((Report *)reports[2]).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"something.else"]);

            assertWithTimeout(1.0, thatEventually(@([redImport isFinished] && [blueImport isFinished])), isTrue());
        });

        it(@"removes reports with path that does not exist and are not importing", ^{

            [fileManager createPaths:@"report1.red", @"report2.blue", nil];

            TestImportProcess *redImport = redType.enqueueImport;
            TestImportProcess *blueImport = blueType.enqueueImport;

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled && blueImport.report.isEnabled)), isTrue());

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            [fileManager createPaths:@"report2.blue", nil];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports[0]).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

        it(@"leaves imported and importing reports in order of discovery", ^{

            [fileManager createPaths:@"report1.red", @"report2.blue", @"report3.red", nil];

            TestImportProcess *blueImport = [blueType.enqueueImport block];
            TestImportProcess *redImport1 = [redType enqueueImport];
            TestImportProcess *redImport2 = [redType enqueueImport];

            NSArray<Report *> *reports1 = [NSArray arrayWithArray:[store loadReports]];

            expect(reports1.count).to.equal(3);
            expect(reports1[0].rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(reports1[1].rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(reports1[2].rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);

            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && redImport2.isFinished)), isTrue());

            [fileManager createPaths:@"report2.blue", @"report3.red", @"report11.red", nil];
            redImport1 = [redType enqueueImport];

            NSArray<Report *> *reports2 = [NSArray arrayWithArray:[store loadReports]];

            expect(reports2.count).to.equal(3);
            expect(reports2[0].rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(reports2[0]).to.beIdenticalTo(reports1[1]);
            expect(reports2[1].rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);
            expect(reports2[1]).to.beIdenticalTo(reports1[2]);
            expect(reports2[2].rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report11.red"]);
            expect(reports2[2]).notTo.beIdenticalTo(reports1[0]);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && blueImport.report.isEnabled)), isTrue());
        });

        it(@"leaves reports whose path may not exist but are still importing", ^{

            [fileManager createPaths:@"report1.red", @"report2.blue", nil];

            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSArray<Report *> *reports = [store loadReports];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(redImport.isFinished).to.equal(NO);
            expect([reports[0] isEnabled]).to.equal(NO);
            expect([reports[1] isEnabled]).to.equal(YES);

            Report *redReport = redImport.report;
            redReport.rootFile = [reportsDir URLByAppendingPathComponent:@"report1.transformed"];

            [fileManager createPaths:@"report1.transformed", nil];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports.firstObject).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.transformed"]);
            expect(((Report *)reports.firstObject).isEnabled).to.equal(NO);

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            expect(store.reports.count).to.equal(1);
            expect(((Report *)store.reports.firstObject).rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.transformed"]);
            expect(((Report *)store.reports.firstObject).isEnabled).to.equal(YES);
        });

        it(@"leaves failed download reports", ^{
            failure(@"TODO: is this what we want?");
        });

        it(@"sends notifications about added reports", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil];

            [fileManager createPaths:@"report1.red", @"report2.blue", nil];

            [redType.enqueueImport cancelAll];
            [blueType.enqueueImport cancelAll];

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(2));

            [observer.received enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSNotification *note = [obj notification];
                Report *report = note.userInfo[@"report"];

                expect(note.name).to.equal(ReportNotification.reportAdded);
                expect(report).to.beIdenticalTo(reports[idx]);
            }];

            [notifications removeObserver:observer];
        });

        it(@"posts a reports loaded notification", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportsLoaded on:notifications from:store withBlock:nil];
            [store loadReports];

            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(1));
        });

    });

    xdescribe(@"importing stand-alone files from the documents directory", ^{

        it(@"imports a report with the capable report type", ^{

            [fileManager createPaths:@"report.red", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(store.reports).to.haveCountOf(1);
            expect(store.reports).to.contain(report);
            expect(report).to.beIdenticalTo(redImport.report);
        });

        it(@"moves source file to base dir in import dir before importing", ^{

            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"report.red"];
            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"report.red.dice_import" isDirectory:YES];
            NSURL *baseDir = [importDir URLByAppendingPathComponent:@"dice_content" isDirectory:YES];
            NSURL *rootFile = [baseDir URLByAppendingPathComponent:sourceFile.lastPathComponent];

            __block atomic_bool assignedToReportBeforeCreated; atomic_init(&assignedToReportBeforeCreated, NO);
            __block atomic_bool createdImportDirOnMainThread; atomic_init(&createdImportDirOnMainThread, NO);
            __block atomic_bool sourceFileMoved; atomic_init(&sourceFileMoved, NO);
            __block atomic_bool movedOnBackgroundThread; atomic_init(&movedOnBackgroundThread, NO);
            __block atomic_bool movedBeforeImport; atomic_init(&movedBeforeImport, NO);

            __block Report *report;

            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *path, BOOL createIntermediates, NSError **err) {
                if ([path isEqualToString:importDir.path]) {
                    atomic_store((atomic_bool *)&createdImportDirOnMainThread, NSThread.isMainThread);
                }
                else if ([path isEqualToString:baseDir.path]) {
                    BOOL val = [report.baseDir.path isEqualToString:path] && [report.rootFile isEqual:rootFile] && createIntermediates;
                    atomic_store((atomic_bool *)&assignedToReportBeforeCreated, val);
                }
                return YES;
            };
            fileManager.onMoveItemAtPath = ^BOOL(NSString *sourcePath, NSString *destPath, NSError *__autoreleasing *error) {
                if ([sourcePath isEqualToString:sourceFile.path] && [destPath isEqualToString:rootFile.path]) {
                    atomic_store((atomic_bool *)&sourceFileMoved, [report.rootFile isEqual:rootFile]);
                    atomic_store((atomic_bool *)&movedOnBackgroundThread, !NSThread.isMainThread);
                }
                return YES;
            };
            TestImportProcess *importProcess = [[redType enqueueImport] block];
            importQueue.onAddOperation = ^(NSOperation *op) {
                if (op == importProcess.steps.firstObject) {
                    atomic_store((atomic_bool *)&movedBeforeImport, (_Bool)sourceFileMoved);
                }
            };

            [fileManager createPaths:sourceFile.lastPathComponent, nil];
            report = [store attemptToImportReportFromResource:sourceFile];

            expect(report.sourceFile).to.equal(sourceFile);

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            expect(atomic_load((atomic_bool *)&sourceFileMoved)).to.beTruthy();

            [importProcess unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(report.sourceFile).to.equal(sourceFile);
            expect(report.importDir).to.equal(importDir);
            expect(report.baseDir).to.equal(baseDir);
            expect(report.rootFile).to.equal(rootFile);
            expect(atomic_load((atomic_bool *)&assignedToReportBeforeCreated)).to.beTruthy();
            expect(atomic_load((atomic_bool *)&movedBeforeImport)).to.beTruthy();
            expect(atomic_load((atomic_bool *)&movedOnBackgroundThread)).to.beTruthy();
        });

        it(@"posts a notification when the import begins", ^{

            [fileManager createPaths:@"report.red", nil];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver
                observe:ReportNotification.reportImportBegan on:store.notifications from:store withBlock:nil];
            [redType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(observer.received.count).to.equal(1);

            ReceivedNotification *received = observer.received.lastObject;
            NSNotification *note = received.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusSuccess);
            expect(received.wasMainThread).to.equal(YES);
        });

        it(@"posts a notification when the import finishes successfully", ^{

            [fileManager createPaths:@"report.red", nil];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver
                observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
            [redType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            ReceivedNotification *received = observer.received.lastObject;
            NSNotification *note = received.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusSuccess);
            expect(received.wasMainThread).to.equal(YES);
        });

        it(@"posts a notification when the import finishes unsuccessfully", ^{

            [fileManager createPaths:@"report.red", nil];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver
                observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
            TestImportProcess *redImport = [redType enqueueImport];
            [redImport.steps.firstObject cancel];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            ReceivedNotification *received = observer.received.lastObject;
            NSNotification *note = received.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
            expect(received.wasMainThread).to.equal(YES);
        });

        it(@"returns a report even if the url cannot be imported", ^{

            [fileManager createPaths:@"report.green", nil];
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(report).notTo.beNil();
            expect(report.sourceFile).to.equal(url);
            expect(store.reports).to.contain(report);
        });

        it(@"assigns an error message if the report type was unknown", ^{

            [fileManager createPaths:@"report.green", nil];
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusFailed));

            expect(report.summary).to.equal(@"Unknown content type");
        });

        it(@"immediately adds the report to the report list", ^{

            [fileManager createPaths:@"report.red", nil];
            TestImportProcess *import = [[redType enqueueImport] block];
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(store.reports).to.contain(report);

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            expect(report.title).to.equal(report.sourceFile.lastPathComponent);
            expect(report.summary).to.equal(@"Importing content...");
            expect(report.isEnabled).to.equal(NO);
            
            [import unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(store.reports).to.contain(report);
        });

        it(@"sends a notification serially about adding the report", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil];

            TestImportProcess *importProcess = [[redType enqueueImport] block];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            expect(observer.received.count).to.equal(1);

            ReceivedNotification *received = observer.received.firstObject;
            Report *receivedReport = received.notification.userInfo[@"report"];
            expect(received.notification.name).to.equal(ReportNotification.reportAdded);
            expect(receivedReport).to.beIdenticalTo(report);

            [importProcess unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            [notifications removeObserver:observer];
        });

        it(@"does not start an import for a report file already importing", ^{

            [fileManager createPaths:@"report1.red", nil];
            TestImportProcess *import = [[redType enqueueImport] block];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver
                observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil];
            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];
            Report *report = [store attemptToImportReportFromResource:reportUrl];
            Report *reportAgain = [store attemptToImportReportFromResource:reportUrl];

            expect(store.reports).to.haveCountOf(1);
            expect(reportAgain).to.beIdenticalTo(report);
            expect(observer.received).to.haveCountOf(1);
            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(report);
            expect(store.reports).to.haveCountOf(1);
            expect(store.reports.firstObject).to.beIdenticalTo(notificationReport);

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            notificationReport = nil;
            [observer.received removeAllObjects];

            Report *sameReport = [store attemptToImportReportFromResource:reportUrl];

            [import unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(sameReport).to.beIdenticalTo(report);
            expect(store.reports).to.haveCountOf(1);
            expect(observer.received).to.haveCountOf(0);

            [notifications removeObserver:observer];
        });

        it(@"removes special characters from file name to make import dir", ^{
            failure(@"unimplemented");
        });

        it(@"posts a failure notification if no report type matches the content", ^{

            [fileManager createPaths:@"oops.der", nil];
            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"oops.der"]];

            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(1));

            NSNotification *note = obs.received.firstObject.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
        });

        it(@"can retry a failed import after deleting the report", ^{

            NSURL *url = [reportsDir URLByAppendingPathComponent:@"oops.bloo"];
            [fileManager createPaths:url.lastPathComponent, nil];
            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            NSNotification *note = obs.received.firstObject.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);

            [store deleteReport:report];

            assertWithTimeout(1.0, thatEventually(store.reports), isNot(contains(report, nil)));

            [fileManager createPaths:url.lastPathComponent, nil];

            Report *retry = [store attemptToImportReportFromResource:url];

            expect(retry).toNot.beIdenticalTo(report);

            assertWithTimeout(1.0, thatEventually(@(retry.isImportFinished)), isTrue());

            expect(retry.importStatus).to.equal(ReportImportStatusFailed);
            expect(obs.received).to.haveCountOf(2);
            expect(obs.received[0].notification.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(obs.received[1].notification.userInfo[@"report"]).to.beIdenticalTo(retry);
        });

        it(@"writes the report record to the import dir", ^{

            NSURL *url = [reportsDir URLByAppendingPathComponent:@"thing.blue"];
            [blueType enqueueImport];

            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            NSURL *record = [report.importDir URLByAppendingPathComponent:@"dice.obj"];

            expect([fileManager fileExistsAtPath:record.path]).to.beTruthy();

            NSData *recordData = [fileManager contentsAtPath:record.path];
            Report *saved = nil; // TODO: NSCoding stuff

            failure(@"implement persistence");
        });

        xit(@"passees the content match predicate to the import process", ^{
            /*
             TODO: Allow the ReportContentMatchPredicate to pass information to
             the ImportProcess about what was found in the archive.  this will
             help support alternatives to the standard index.html assumption by
             potentially allowing the ImportProcess to rename or symlink html
             resources found during the archive entry enumeration.
             Also the HtmlReportType should do a breadth first search for html
             files, or at least in the base dir.  also maybe restore the fail-
             fast element of the ReportTypeMatchPredicate, e.g., if index.html
             exists at the root, stop immediately.  Possibly reuse the ReportContentMatchPredicate
             for enumerating file system contents.
             */
            failure(@"do it");
        });

    });

    xdescribe(@"importing exploded directories", ^{

        // TODO: the utility of this is debatable

        it(@"sets the base dir when there is one", ^{

            [fileManager createPaths:@"blue.dice_import/", @"blue.dice_import/blue_base/", @"blue.dice_import/blue_base/index.blue", nil];
            TestImportProcess *blueImport = [[blueType enqueueImport] block];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue.dice_import" isDirectory:YES]];

            expect(report.baseDir).to.equal([reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]);
            expect(report.rootFile).to.equal(report.baseDir);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(report.importDir).to.equal([reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]);
            expect(report.rootFile).to.equal([reportsDir URLByAppendingPathComponent:@"blue_base/index.blue"]);
        });

        it(@"sets the root file to the source file in the import dir if the import process doesn't set the root file", ^{
            
        });

        it(@"parses the report descriptor if present in base dir as metadata.json", ^{

            [fileManager createPaths:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", nil];
            [fileManager createFilePath:@"blue_base/metadata.json" contents:
                [@"{\"title\": \"Title From Descriptor\", \"description\": \"Summary from descriptor\"}"
                    dataUsingEncoding:NSUTF8StringEncoding]];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:baseDir];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(report.title).to.equal(@"Title From Descriptor");
            expect(report.summary).to.equal(@"Summary from descriptor");
        });

        it(@"parses the report descriptor if present in base dir as dice.json", ^{

            [fileManager createPaths:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", nil];
            [fileManager createFilePath:@"blue_base/dice.json" contents:
                [@"{\"title\": \"Title From Descriptor\", \"description\": \"Summary from descriptor\"}"
                    dataUsingEncoding:NSUTF8StringEncoding]];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:baseDir];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(report.title).to.equal(@"Title From Descriptor");
            expect(report.summary).to.equal(@"Summary from descriptor");
        });

        it(@"prefers dice.json to metadata.json", ^{

            [fileManager createPaths:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", @"blue_base/dice.json", nil];
            [fileManager createFilePath:@"blue_base/dice.json" contents:
                [@"{\"title\": \"Title From dice.json\", \"description\": \"Summary from dice.json\"}"
                    dataUsingEncoding:NSUTF8StringEncoding]];
            [fileManager createFilePath:@"blue_base/metadata.json" contents:
                [@"{\"title\": \"Title From metadata.json\", \"description\": \"Summary from metadata.json\"}"
                    dataUsingEncoding:NSUTF8StringEncoding]];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:baseDir];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(report.title).to.equal(@"Title From dice.json");
            expect(report.summary).to.equal(@"Summary from dice.json");
        });

        it(@"sets a nil summary if the report descriptor is unavailable", ^{

            [fileManager createPaths:@"blue_base/", @"blue_base/index.blue", nil];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:baseDir];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(report.summary).to.beNil();
        });

        it(@"works if the import process changes the report url", ^{

            [fileManager createPaths:@"blue_base/", @"blue_base/index.blue", nil];
            TestImportProcess *blueImport = [blueType enqueueImport];
            blueImport.steps = @[
                [NSBlockOperation blockOperationWithBlock:^{
                    blueImport.report.rootFile = [reportsDir URLByAppendingPathComponent:@"blue_base/index.blue"];
                }],
                [[NSBlockOperation blockOperationWithBlock:^{}] block]
            ];

            Report *report1 = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]];

            assertWithTimeout(1.0, thatEventually(report1.rootFile), equalTo([reportsDir URLByAppendingPathComponent:@"blue_base/index.blue"]));

            Report *report2 = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]];

            expect(report2).to.beIdenticalTo(report1);
            expect(store.reports.count).to.equal(1);
            expect(store.reports.firstObject).to.beIdenticalTo(report1);

            [blueImport.steps[1] unblock];

            assertWithTimeout(1.0, thatEventually(@(report1.isEnabled)), isTrue());

            expect(store.reports.count).to.equal(1);
            expect(store.reports.firstObject).to.beIdenticalTo(report1);

            report2 = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]];
            
            expect(report2).to.beIdenticalTo(report1);
            expect(report2.isEnabled).to.equal(YES);
        });

    });

    // MARK: - Importing archives

    describe(@"importing report archives from the documents directory", ^{

        it(@"creates an import dir for the archive", ^{

            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            [fileManager createPaths:@"blue.zip", nil];
            TestImportProcess *blueImport = [[blueType enqueueImport] block];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
            __block Report *report;
            __block BOOL createdImportDir = NO;
            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *path, BOOL createIntermediates, NSError *__autoreleasing *error) {
                if ([path isEqualToString:importDir.path]) {
                    createdImportDir = [report.importDir isEqual:importDir] && NSThread.isMainThread;
                }
                return YES;
            };

            report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusExtracting));

            expect(report.sourceFile).to.equal(archiveUrl);
            expect(report.importDir).to.equal(importDir);
            expect(createdImportDir).to.beTruthy();

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
        });

        it(@"creates a base dir if the archive has no base dir", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [[blueType enqueueImport] block];
            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
            NSURL *baseDir = [importDir URLByAppendingPathComponent:@"dice_content" isDirectory:YES];
            __block BOOL createdBaseDir = NO;
            __block Report *report;
            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *path, BOOL intermediates, NSError **error) {
                createdBaseDir = [path isEqualToString:baseDir.path];
                return YES;
            };

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusExtracting));

            expect(createdBaseDir).to.beTruthy();

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            expect(report.baseDir).to.equal(baseDir);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not create a new base dir if archive has base dir", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [[blueType enqueueImport] block];
            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
            NSURL *baseDir = [importDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            __block BOOL createdArchiveBaseDir = NO;
            __block BOOL createdUnexpectedDir = NO;
            __block Report *report;

            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *path, BOOL intermediates, NSError **error) {
                if ([path isEqualToString:baseDir.path]) {
                    // the archive extraction implicitly creates base dir on background thread
                    createdArchiveBaseDir = [report.baseDir isEqual:baseDir] && report.importStatus == ReportImportStatusExtracting && !NSThread.isMainThread;
                }
                else {
                    createdUnexpectedDir = ![path isEqualToString:importDir.path];
                }
                return YES;
            };

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusExtracting));

            expect(report.baseDir).to.equal(baseDir);

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            expect(createdArchiveBaseDir).to.beTruthy();

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(createdUnexpectedDir).to.beFalsy();

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"deletes the archive file after extracting the contents", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [[blueType enqueueImport] block];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DeleteFileOperation *deleteArchive;
            __block BOOL queuedOnMainThread = NO;
            __block BOOL multipleDeletes = NO;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    DeleteFileOperation *del = (DeleteFileOperation *)op;
                    if ([del.fileUrl isEqual:archiveUrl]) {
                        if (deleteArchive) {
                            multipleDeletes = YES;
                            return;
                        }
                        queuedOnMainThread = NSThread.isMainThread;
                        deleteArchive = [del block];
                    }
                }
            };

            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.beTruthy();

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            expect(deleteArchive).toNot.beNil();
            expect(queuedOnMainThread).to.beTruthy();
            expect(multipleDeletes).to.beFalsy();

            [deleteArchive unblock];

            assertWithTimeout(1.0, thatEventually(@(deleteArchive.isFinished)), isTrue());

            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.beFalsy();
            expect(report.importStatus).to.equal(ReportImportStatusImporting);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            [importQueue waitUntilAllOperationsAreFinished];

            expect(multipleDeletes).to.beFalsy();
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not delete the archive file if the extract fails", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return nil;
                };
            }];

            __block DICEExtractReportOperation *extract;
            __block DeleteFileOperation *deleteArchive;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    extract = (DICEExtractReportOperation *)op;
                    [extract cancel];
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteArchive = (DeleteFileOperation *)op;
                }
            };

            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.equal(YES);

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            [importQueue waitUntilAllOperationsAreFinished];

            expect(extract).toNot.beNil();
            expect(extract.wasSuccessful).to.beFalsy();
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.equal(YES);
            expect(deleteArchive).to.beNil();
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes import status to extracting and posts update notification", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DICEExtractReportOperation *extract;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [extract block];
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportExtractProgress on:notifications from:store withBlock:nil];

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToUnsignedInteger(1));

            ReceivedNotification *received = observer.received.firstObject;
            NSNotification *note = received.notification;

            expect(received.wasMainThread).to.equal(YES);
            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusExtracting);

            [extract unblock];

            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"posts notifications about extract progress", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:(1 << 20)]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            [blueType enqueueImport];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];
            NSMutableArray<NSNotification *> *extractUpdates = [NSMutableArray array];
            __block NSNotification *finished = nil;
            [store.notifications addObserverForName:ReportNotification.reportExtractProgress object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
                [extractUpdates addObject:note];
            }];
            [store.notifications addObserverForName:ReportNotification.reportImportFinished object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
                finished = note;
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(finished), notNilValue());

            expect(extractUpdates.count).to.beGreaterThan(10);
            expect(extractUpdates.lastObject.userInfo[@"percentExtracted"]).to.equal(@100);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"load reports does not create multiple reports while the archive is extracting", ^{

            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            [fileManager createPaths:archiveUrl.lastPathComponent, nil];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DICEExtractReportOperation *extract;
            __block BOOL multipleExtracts = NO;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (!NSThread.isMainThread) {
                        [NSException raise:NSInternalInconsistencyException format:@"added extract operation from background thread"];
                    }
                    if (extract != nil) {
                        multipleExtracts = YES;
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [extract block];
                }
            };

            NSArray<Report *> *reports1 = [[store loadReports] copy];
            Report *report = reports1.firstObject;

            expect(reports1.count).to.equal(1);
            expect(report.sourceFile).to.equal(archiveUrl);

            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());

            NSUInteger opCount = importQueue.operationCount;

            NSArray *reports2 = [[store loadReports] copy];

            expect(reports2.count).to.equal(reports1.count);
            expect(reports2.firstObject).to.beIdenticalTo(report);
            expect(importQueue.operationCount).to.equal(opCount);

            [blueType enqueueImport];
            [extract unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(multipleExtracts).to.beFalsy();

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"single import does not create multiple reports while the archive is extracting", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DICEExtractReportOperation *extract;
            __block BOOL multipleExtracts = NO;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (!NSThread.isMainThread) {
                        [NSException raise:NSInternalInconsistencyException format:@"added extract operation from background thread"];
                    }
                    if (extract != nil) {
                        multipleExtracts = YES;
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [extract block];
                }
            };

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());

            NSURL *importDir = report.importDir;
            NSURL *importDirParent = importDir.URLByDeletingLastPathComponent;

            expect(importDir).toNot.beNil();
            expect(importDirParent.pathComponents).to.equal(reportsDir.pathComponents);

            NSUInteger opCount = importQueue.operationCount;

            Report *dupFromArchiveUrl = [store attemptToImportReportFromResource:archiveUrl];
            Report *dupFromImportDir = [store attemptToImportReportFromResource:report.importDir];

            expect(dupFromArchiveUrl).to.beIdenticalTo(report);
            expect(dupFromImportDir).to.beIdenticalTo(report);
            expect(store.reports).to.haveCountOf(1);
            expect(importQueue.operationCount).to.equal(opCount);

            [blueType enqueueImport];
            [extract unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(multipleExtracts).to.beFalsy();

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not start an import process if the extraction fails", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    *errOut = [[NSError alloc] initWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"error for test"}];
                    return nil;
                };
            }];

            // intentionally do not enqueue import process to force failure if attempted
            // TestImportProcess *blueImport = [blueType enqueueImport];

            __block DICEExtractReportOperation *extract;
            __block BOOL multipleExtracts = NO;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (!NSThread.isMainThread) {
                        [NSException raise:NSInternalInconsistencyException format:@"added extract operation from background thread"];
                    }
                    if (extract != nil) {
                        multipleExtracts = YES;
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                }
            };

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusFailed));

            expect(extract.isFinished).to.equal(YES);
            expect(extract.wasSuccessful).to.equal(NO);
            expect(multipleExtracts).to.beFalsy();

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"posts failure notification if extract fails", ^{

            [fileManager createPaths:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    *errOut = [[NSError alloc] initWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"error for test"}];
                    return nil;
                };
            }];

            // intentionally do not enqueue import process to force failure if attempted
            // TestImportProcess *blueImport = [blueType enqueueImport];

            __block DICEExtractReportOperation *extract;
            __block BOOL multipleExtracts = NO;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if (!NSThread.isMainThread) {
                    [NSException raise:NSInternalInconsistencyException format:@"queued extract operation from background thread"];
                }
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        multipleExtracts = YES;
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                }
            };

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(1));
            
            expect(extract.isFinished).to.equal(YES);
            expect(extract.wasSuccessful).to.equal(NO);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
            expect(report.summary).to.equal(@"Failed to extract archive contents");

            ReceivedNotification *received = observer.received.lastObject;
            NSNotification *note = received.notification;

            expect(received.wasMainThread).to.equal(YES);
            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            
            [NSFileHandle deswizzleAllClassMethods];
        });

    });

    describe(@"restoring previously imported content", ^{

        it(@"loads persisted record", ^{

            Report *report = [[Report alloc] init];

            [fileManager createPaths:
                @"restore.dice_import/",
                @"restore.dice_import/dice.obj",
                @"restore.dice_import/dice_content/",
                @"restore.dice_import/dice_content/index.blue",
                nil];

            [fileManager createFilePath:@"restore.dice_import/dice.obj" contents:[NSKeyedArchiver archivedDataWithRootObject:report]];
        });

        it(@"treats an import dir as a stand-alone documents dir", ^{
            failure(@"to do");
        });

        it(@"materializes the report record from the stored import record in the import dir", ^{
            failure(@"to do");
        });
    });

#pragma mark - Downloading

    xdescribe(@"downloading content", ^{

        it(@"starts a download when importing from an http url", ^{
        
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report"];
            Report *report = [store attemptToImportReportFromResource:url];

            [verify(downloadManager) downloadUrl:url];
            expect(report.importStatus).to.equal(ReportImportStatusDownloading);
            expect(store.reports).to.contain(report);
        });

        it(@"starts a download when importing from an https url", ^{

            NSURL *url = [NSURL URLWithString:@"https://dice.com/report"];
            Report *report = [store attemptToImportReportFromResource:url];

            [verify(downloadManager) downloadUrl:url];
            expect(report.importStatus).to.equal(ReportImportStatusDownloading);
            expect(store.reports).to.contain(report);
        });

        it(@"posts a report added notification before the download begins", ^{

            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportAdded on:store.notifications from:store withBlock:nil];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(1));

            ReceivedNotification *received = obs.received.firstObject;
            NSNotification *note = received.notification;
            NSDictionary *userInfo = note.userInfo;

            expect(userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusDownloading);
        });

        it(@"posts download progress notifications", ^{

            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:nil];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 12345;
            Report *report = [store attemptToImportReportFromResource:url];
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];

            expect(obs.received).to.haveCountOf(1);

            ReceivedNotification *received = obs.received.firstObject;
            NSNotification *note = received.notification;
            NSDictionary *userInfo = note.userInfo;

            expect(userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.downloadProgress).to.equal(1);
        });

        it(@"posts download finished notification", ^{

            TestImportProcess *import = [blueType enqueueImport];
            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadComplete on:store.notifications from:store withBlock:nil];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 999999;
            download.downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
            Report *report = [store attemptToImportReportFromResource:url];

            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:download.downloadedFile];
            download.wasSuccessful = YES;
            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(@(import.isFinished)), isTrue());

            ReceivedNotification *received = obs.received.firstObject;
            NSNotification *note = received.notification;
            NSDictionary *userInfo = note.userInfo;

            expect(obs.received).to.haveCountOf(1);
            expect(userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.downloadProgress).to.equal(100);
        });

        it(@"does not post a progress notification if the percent complete did not change", ^{

            __block NSInteger lastProgress = 0;
            NotificationRecordingObserver *obs = [[NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:^(NSNotification *notification) {
                if (![ReportNotification.reportDownloadProgress isEqualToString:notification.name]) {
                    return;
                }
                Report *report = notification.userInfo[@"report"];
                if (lastProgress == report.downloadProgress) {
                    failure([NSString stringWithFormat:@"duplicate progress notifications: %@", @(lastProgress)]);
                }
                lastProgress = report.downloadProgress;
            }] observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];

            TestImportProcess *import = [blueType enqueueImport];
            import.steps = @[[NSBlockOperation blockOperationWithBlock:^{}]];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            Report *report = [store attemptToImportReportFromResource:url];

            download.bytesReceived = 12345;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 12500;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 99999;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 999999;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            download.downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
            [store downloadManager:downloadManager willFinishDownload:download movingToFile:download.downloadedFile];
            download.wasSuccessful = YES;
            [store downloadManager:downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            ReceivedNotification *received = obs.received.lastObject;
            NSNotification *note = received.notification;
            NSDictionary *userInfo = note.userInfo;

            expect(obs.received).to.haveCountOf(4);
            expect(obs.received.lastObject.notification.name).to.equal(ReportNotification.reportDownloadComplete);
            expect(userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.downloadProgress).to.equal(100);
        });

        it(@"posts a progress notification about a url that did not match a report", ^{

            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:nil];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 999999;
            [store attemptToImportReportFromResource:url];
            DICEDownload *foreignDownload = [[DICEDownload alloc] initWithUrl:[NSURL URLWithString:@"http://not.a.report/i/know/about.blue"]];

            [store downloadManager:store.downloadManager didReceiveDataForDownload:foreignDownload];
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];

            expect(obs.received).to.haveCountOf(2);
        });

        it(@"begins an import for the same report after the download is complete", ^{

            TestImportProcess *blueImport = [[blueType enqueueImport] block];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            Report *report = [store attemptToImportReportFromResource:url];
            download.bytesReceived = 555555;
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 999999;
            url = [reportsDir URLByAppendingPathComponent:@"report.blue"];
            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:url];
            [fileManager createFileAtPath:url.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
            download.wasSuccessful = YES;
            download.downloadedFile = url;
            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToInteger(ReportImportStatusImporting));

            expect(blueImport.report).to.beIdenticalTo(report);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(blueImport.isFinished)), isTrue());
        });

        it(@"responds to failed downloads", ^{

            TestImportProcess *import = [blueType enqueueImport];
            import.steps = @[[NSBlockOperation blockOperationWithBlock:^{
                failure(@"erroneously started import process for failed download");
            }]];
            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:store.notifications from:store withBlock:nil];
            [obs observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 0;
            download.downloadedFile = nil;
            download.wasSuccessful = NO;
            download.httpResponseCode = 503;

            Report *report = [store attemptToImportReportFromResource:url];

            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(obs.received.lastObject.notification.name), equalTo(ReportNotification.reportImportFinished));

            expect(obs.received).to.haveCountOf(1);
            expect(obs.received.lastObject.notification.name).to.equal(ReportNotification.reportImportFinished);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
            expect(report.isEnabled).to.beFalsy();
        });

        it(@"can import a downloaded archive file", ^{

            NSURL *downloadUrl = [NSURL URLWithString:@"http://dice.com/report.zip"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:downloadUrl];
            download.bytesExpected = 999999;
            Report *report = [store attemptToImportReportFromResource:downloadUrl];
            download.bytesReceived = 555555;
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 999999;
            NSURL *downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.zip"];
            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:downloadedFile];
            [fileManager createFileAtPath:downloadUrl.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
            download.wasSuccessful = YES;
            download.downloadedFile = downloadedFile;
            download.mimeType = @"application/zip";
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:999999 sizeExtracted:999999]
            ] archiveUrl:downloadedFile archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:downloadedFile withUti:kUTTypeZipArchive]) willReturn:archive];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];
            TestImportProcess *blueImport = [blueType enqueueImport];

            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isImportFinished)), isTrue());

            expect(report.importStatus).to.equal(ReportImportStatusSuccess);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"can re-download the same url after failing to import a downloaded file", ^{

            failure(@"implement prompt to overwrite file with download");
            failure(@"actually this isn't even possible right now because the download url is lost after the download completes");
            failure(@"use CoreData to track where reports come from");

//            TestImportProcess *importProcess = [blueType enqueueImport];
//            importProcess.steps = @[[NSBlockOperation blockOperationWithBlock:^{
//                importProcess.failed = YES;
//            }]];
//
//            NotificationRecordingObserver *obs = [[[[[NotificationRecordingObserver
//                observe:ReportNotification.reportAdded on:store.notifications from:store withBlock:nil]
//                observe:ReportNotification.reportRemoved on:store.notifications from:store]
//                observe:ReportNotification.reportImportFinished on:store.notifications from:store]
//                observe:ReportNotification.reportDownloadProgress on:store.notifications from:store]
//                observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];
//
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            NSURL *downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            download.bytesReceived = 999999;
//            download.downloadedFile = downloadedFile;
//            download.wasSuccessful = YES;
//            download.httpResponseCode = 200;
//
//            Report *report = [store attemptToImportReportFromResource:url];
//            [store downloadManager:downloadManager willFinishDownload:download movingToFile:downloadedFile];
//            [store downloadManager:downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(obs.received.lastObject.notification.name), equalTo(ReportNotification.reportImportFinished));
//
//            expect(store.reports).to.contain(report);
//            expect(report.importStatus).to.equal(ReportImportStatusFailed);
//            NSArray<ReceivedNotification *> *received = obs.received;
//            expect(received).to.haveCountOf(3);
//            expect(received[0].notification.name).to.equal(ReportNotification.reportAdded);
//            expect(received[1].notification.name).to.equal(ReportNotification.reportDownloadComplete);
//            expect(received[2].notification.name).to.equal(ReportNotification.reportImportFinished);

        });

        it(@"can re-download the same url after a download fails", ^{

            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:store.notifications from:store withBlock:nil];
            [obs observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 0;
            download.downloadedFile = nil;
            download.wasSuccessful = NO;
            download.httpResponseCode = 503;

            Report *report = [store attemptToImportReportFromResource:url];

            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(obs.received.lastObject.notification.name), equalTo(ReportNotification.reportImportFinished));

            expect(obs.received).to.haveCountOf(1);
            expect(obs.received.lastObject.notification.name).to.equal(ReportNotification.reportImportFinished);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
            expect(report.title).to.equal(@"Download failed");
            expect(report.isEnabled).to.beFalsy();
            expect(store.reports).to.contain(report);

            [store.notifications removeObserver:obs];
            obs = [[[[NotificationRecordingObserver
                observe:ReportNotification.reportAdded on:store.notifications from:store withBlock:nil]
                observe:ReportNotification.reportImportFinished on:store.notifications from:store]
                observe:ReportNotification.reportDownloadProgress on:store.notifications from:store]
                observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];

            Report *retryReport = [store attemptToImportReportFromResource:url];

            expect(retryReport).to.beIdenticalTo(report);
            expect(retryReport.importStatus).to.equal(ReportImportStatusDownloading);
            expect(obs.received).to.haveCountOf(0);
            [verifyCount(downloadManager, times(2)) downloadUrl:url];

            download.bytesReceived = 555555;
            download.httpResponseCode = 200;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            expect(report.importStatus).to.equal(ReportImportStatusDownloading);
            expect(report.downloadProgress).to.equal(download.percentComplete);

            [blueType enqueueImport];
            NSURL *downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
            [store downloadManager:downloadManager willFinishDownload:download movingToFile:downloadedFile];
            download.wasSuccessful = YES;
            download.downloadedFile = downloadedFile;
            [store downloadManager:downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
            expect(report.isEnabled).to.beTruthy();
            expect(report.rootFile).to.equal(downloadedFile);
            expect(report.importStatus).to.equal(ReportImportStatusSuccess);

            NSArray<ReceivedNotification *> *received = obs.received;
            expect(received).to.haveCountOf(3);
            expect(received[0].notification.name).to.equal(ReportNotification.reportDownloadProgress);
            expect(received[1].notification.name).to.equal(ReportNotification.reportDownloadComplete);
        });

        it(@"does not import downloads finished in the background", ^{
            failure(@"do it");
        });

        it(@"creates reports for download notifications with no report", ^{

            NotificationRecordingObserver *obs = [[[NotificationRecordingObserver
                observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil]
                observe:ReportNotification.reportDownloadProgress on:notifications from:store]
                observe:ReportNotification.reportDownloadComplete on:notifications from:store];
            DICEDownload *inProgress = [[DICEDownload alloc] initWithUrl:[NSURL URLWithString:@"http://dice.com/test.blue"]];
            inProgress.bytesExpected = 9876543;
            inProgress.bytesReceived = 8765432;
            DICEDownload *finished = [[DICEDownload alloc] initWithUrl:[NSURL URLWithString:@"http://dice.com/test.red"]];
            finished.bytesReceived = finished.bytesExpected = 1234567;
            NSURL *finishedFile = [reportsDir URLByAppendingPathComponent:@"test.red"];

            [store downloadManager:downloadManager didReceiveDataForDownload:inProgress];
            [store downloadManager:downloadManager willFinishDownload:finished movingToFile:finishedFile];

            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(3));

            expect(obs.received[0].notification.name).to.equal(ReportNotification.reportAdded);
            expect(obs.received[1].notification.name).to.equal(ReportNotification.reportDownloadProgress);
            expect(obs.received[2].notification.name).to.equal(ReportNotification.reportAdded);

            Report *inProgressReport = obs.received[0].notification.userInfo[@"report"];
            Report *finishedReport = obs.received[2].notification.userInfo[@"report"];

            expect(inProgressReport.importStatus).to.equal(ReportImportStatusDownloading);
            expect(inProgressReport.rootFile).to.equal(inProgress.url);
            expect(finishedReport.importStatus).to.equal(ReportImportStatusDownloading);
            expect(finishedReport.rootFile).to.equal(finishedFile);
            expect(obs.received[0].notification.userInfo[@"report"]).to.beIdenticalTo(inProgressReport);
            expect(obs.received[1].notification.userInfo[@"report"]).to.beIdenticalTo(inProgressReport);

            [redType enqueueImport];
            finished.wasSuccessful = YES;
            finished.downloadedFile = [reportsDir URLByAppendingPathComponent:@"test.red"];
            [store downloadManager:downloadManager didFinishDownload:finished];

            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(4));

            expect(obs.received[3].notification.name).to.equal(ReportNotification.reportDownloadComplete);
            expect(obs.received[3].notification.userInfo[@"report"]).to.beIdenticalTo(finishedReport);
            expect(finishedReport.importStatus).to.equal(ReportImportStatusNewLocal);

            assertWithTimeout(1.0, thatEventually(@(finishedReport.isImportFinished)), isTrue());
        });

    });

    describe(@"background task handling", ^{

        it(@"starts and ends background task for importing reports", ^{

            [fileManager createPaths:@"test.red", nil];
            [redType enqueueImport];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            assertWithTimeout(1000.0, thatEventually(@(report.isEnabled)), isTrue());

            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [verify(app) endBackgroundTask:backgroundTaskId];
        });

        it(@"begins and ends only one background task for multiple concurrent imports", ^{

            [fileManager createPaths:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.blue"]];

            assertWithTimeout(1000.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [verifyCount(app, never()) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:0];

            [redImport unblock];

            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verify(app) endBackgroundTask:backgroundTaskId];
        });

        it(@"avoids a race condition and does not end the background task until all pending reports are imported", ^{

            [fileManager createPaths:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];

            __block NSOperation *matchRed = nil;
            [importQueue setOnAddOperation:^(NSOperation *op) {
                if ([op isKindOfClass:MatchReportTypeToContentAtPathOperation.class]) {
                    MatchReportTypeToContentAtPathOperation *match = (MatchReportTypeToContentAtPathOperation *) op;
                    if ([match.report.sourceFile.lastPathComponent isEqualToString:@"test.red"]) {
                        matchRed = [match block];
                    }
                }
            }];

            [store loadReports];

            [verifyCount(app, times(1)) beginBackgroundTaskWithName:@"dice.background_import" expirationHandler:anything()];

            assertWithTimeout(1000.0, thatEventually(@(blueImport.report.isEnabled && matchRed != nil)), isTrue());

            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:0];

            [matchRed unblock];
            [redImport unblock];

            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verifyCount(app, never()) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
            [verifyCount(app, times(1)) endBackgroundTask:backgroundTaskId];
        });

        it(@"begins and ends only one background task for loading reports", ^{

            [fileManager createPaths:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [[blueType enqueueImport] block];

            [store loadReports];

            assertWithTimeout(1000.0, thatEventually(@(
                blueImport.report.importStatus == ReportImportStatusImporting &&
                redImport.report.importStatus == ReportImportStatusImporting)), isTrue());

            [verifyCount(app, times(1)) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:0];

            [redImport unblock];

            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verifyCount(app, never()) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:backgroundTaskId];

            [blueImport unblock];

            assertWithTimeout(1000.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
            
            [verifyCount(app, never()) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
            [verify(app) endBackgroundTask:backgroundTaskId];
        });

        it(@"saves the import state and stops the background task when the OS calls the expiration handler", ^{

            // TODO: verify the archive extract points get saved when that's implemented

            [fileManager createPaths:@"test.red", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            NSOperation *step = [[NSBlockOperation blockOperationWithBlock:^{}] block];
            redImport.steps = @[step];
            HCArgumentCaptor *expirationBlockCaptor = [[HCArgumentCaptor alloc] init];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:(id)expirationBlockCaptor];

            assertWithTimeout(1000.0, thatEventually(@(redImport.steps.firstObject.isExecuting)), isTrue());

            void (^expirationBlock)() = expirationBlockCaptor.value;
            expirationBlock();

            [verify(app) endBackgroundTask:backgroundTaskId];

            [redImport.steps.firstObject unblock];

            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isImportFinished)), isTrue());
        });

        it(@"ends the background task when the last import fails", ^{

            [fileManager createPaths:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            TestImportProcess *blueImport = [blueType enqueueImport];
            blueImport.steps = @[[[NSBlockOperation blockOperationWithBlock:^{}] block]];

            [store loadReports];

            assertWithTimeout(1000.0, thatEventually(blueImport.report), notNilValue());
            assertWithTimeout(1000.0, thatEventually(redImport.report), notNilValue());
            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isImportFinished)), isTrue());

            [blueImport cancel];
            [blueImport.steps.firstObject unblock];

            assertWithTimeout(1000.0, thatEventually(@(blueImport.report.isImportFinished)), isTrue());

            [verify(app) endBackgroundTask:backgroundTaskId];
        });

    });

    describe(@"ignoring reserved files in reports dir", ^{

        it(@"can add exclusions", ^{

            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"not-excluded.blue"]];

            expect(report).toNot.beNil();
            expect(store.reports).to.contain(report);

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            [store addReportsDirExclusion:[NSPredicate predicateWithFormat:@"self.lastPathComponent like %@", @"excluded.blue"]];

            [blueType enqueueImport];
            report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"excluded.blue"]];

            expect(report).to.beNil();
            expect(store.reports).to.haveCountOf(1);
        });

    });

    xdescribe(@"deleting reports", ^{

        __block NSURL *trashDir;
        __block Report *singleResourceReport;
        __block Report *baseDirReport;

        beforeEach(^{
            trashDir = [reportsDir URLByAppendingPathComponent:@".dice.trash" isDirectory:YES];
            [fileManager createPaths:@"stand-alone.red", @"blue_base/", @"blue_base/index.blue", @"blue_base/icon.png", nil];
            ImportProcess *redImport = [redType enqueueImport];
            ImportProcess *blueImport = [blueType enqueueImport];
            NSArray<Report *> *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(reports), everyItem(hasProperty(@"isImportFinished", isTrue())));

            singleResourceReport = redImport.report;
            baseDirReport = blueImport.report;
        });

        it(@"performs delete operations at a lower priority and quality of service", ^{

            __block MoveFileOperation *moveToTrash;
            __block DeleteFileOperation *deleteFromTrash;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveToTrash = (MoveFileOperation *)op;
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteFromTrash = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@(moveToTrash != nil && deleteFromTrash != nil)), isTrue());

            expect(moveToTrash.queuePriority).to.equal(NSOperationQueuePriorityHigh);
            expect(moveToTrash.qualityOfService).to.equal(NSQualityOfServiceUserInitiated);
            expect(deleteFromTrash.queuePriority).to.equal(NSOperationQueuePriorityLow);
            expect(deleteFromTrash.qualityOfService).to.equal(NSQualityOfServiceBackground);

            assertWithTimeout(1.0, thatEventually(@(singleResourceReport.importStatus)), equalToUnsignedInteger(ReportImportStatusDeleted));
        });

        it(@"immediately disables the report, sets its summary, status, and sends change notification", ^{

            expect(store.reports).to.contain(singleResourceReport);
            expect(singleResourceReport.isEnabled).to.equal(YES);

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportChanged on:notifications from:store withBlock:nil];
            importQueue.suspended = YES;

            [store deleteReport:singleResourceReport];

            expect(singleResourceReport.isEnabled).to.equal(NO);
            expect(singleResourceReport.importStatus).to.equal(ReportImportStatusDeleting);
            expect(singleResourceReport.statusMessage).to.equal(@"Deleting content...");
            expect(observer.received.count).to.equal(1);
            expect(observer.received.firstObject.notification.userInfo[@"report"]).to.beIdenticalTo(singleResourceReport);

            importQueue.suspended = NO;

            assertWithTimeout(1.0, thatEventually(store.reports), isNot(hasItem(singleResourceReport)));
        });

        it(@"removes the report from the list after moving to the trash dir", ^{

            __block MoveFileOperation *moveOp;
            __block DeleteFileOperation *deleteOp;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveOp = (MoveFileOperation *)[op block];
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteOp = (DeleteFileOperation *)[op block];
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(moveOp), isNot(nilValue()));

            [moveOp unblock];

            assertWithTimeout(1.0, thatEventually(@(moveOp.isFinished)), isTrue());
            assertWithTimeout(1.0, thatEventually(store.reports), isNot(hasItem(singleResourceReport)));

            [deleteOp unblock];
        });

        it(@"sets the report status when finished deleting", ^{

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@(singleResourceReport.importStatus)), equalToUnsignedInteger(ReportImportStatusDeleted));
        });

        it(@"creates the trash dir if it does not exist", ^{

            BOOL isDir = YES;
            expect([fileManager fileExistsAtPath:trashDir.path isDirectory:(BOOL *)&isDir]).to.equal(NO);
            expect(isDir).to.equal(NO);

            __block BOOL createdOnBackgroundThread = NO;
            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *dir, BOOL createIntermediates, NSError *__autoreleasing *err) {
                if ([dir hasPrefix:trashDir.path]) {
                    createdOnBackgroundThread = !NSThread.isMainThread;
                }
                return YES;
            };

            __block DeleteFileOperation *deleteOp;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteOp = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:trashDir.path isDirectory:(BOOL * _Nullable)&isDir] && isDir)), isTrue());
            assertWithTimeout(1.0, thatEventually(@(deleteOp.isFinished)), isTrue());

            expect(createdOnBackgroundThread).to.beTruthy();
        });

        it(@"does not load a report for the trash dir", ^{

            [fileManager createDirectoryAtURL:trashDir withIntermediateDirectories:YES attributes:nil error:NULL];

            NSArray *reports = [store loadReports];

            expect(reports).to.haveCountOf(2);

            assertWithTimeout(1.0, thatEventually(reports), everyItem(hasProperty(@"isImportFinished", @YES)));
        });

        it(@"moves the base dir to a unique trash dir", ^{

            __block MoveFileOperation *moveToTrash;
            __block DeleteFileOperation *deleteFromTrash;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveToTrash = (MoveFileOperation *)op;
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteFromTrash = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:baseDirReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:baseDirReport.baseDir.path])), isFalse());

            expect(moveToTrash).toNot.beNil();
            expect(moveToTrash.sourceUrl).to.equal(baseDirReport.baseDir);
            expect(moveToTrash.destUrl.path).to.beginWith(trashDir.path);

            NSString *reportRelPath = [baseDirReport.baseDir.path pathRelativeToPath:reportsDir.path];
            NSString *reportParentInTrash = [moveToTrash.destUrl.path pathRelativeToPath:trashDir.path];
            reportParentInTrash = reportParentInTrash.pathComponents.firstObject;
            NSUUID *uniqueTrashDirName = [[NSUUID alloc] initWithUUIDString:reportParentInTrash];

            expect(moveToTrash.destUrl.path).to.endWith(reportRelPath);
            expect(uniqueTrashDirName).toNot.beNil();

            assertWithTimeout(1.0, thatEventually(@(deleteFromTrash.isFinished)), isTrue());

            expect(deleteFromTrash.fileUrl).to.equal([trashDir URLByAppendingPathComponent:reportParentInTrash isDirectory:YES]);
        });

        it(@"moves the root resource to a unique trash dir when there is no base dir", ^{

            __block MoveFileOperation *moveToTrash;
            __block DeleteFileOperation *deleteFromTrash;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveToTrash = (MoveFileOperation *)op;
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteFromTrash = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:singleResourceReport.rootFile.path])), isFalse());

            expect(moveToTrash).toNot.beNil();
            expect(moveToTrash.sourceUrl).to.equal(singleResourceReport.rootFile);
            expect(moveToTrash.destUrl.path).to.beginWith(trashDir.path);

            NSString *reportRelPath = [singleResourceReport.rootFile.path pathRelativeToPath:reportsDir.path];
            NSString *reportParentInTrash = [moveToTrash.destUrl.path pathRelativeToPath:trashDir.path];
            reportParentInTrash = reportParentInTrash.pathComponents.firstObject;
            NSUUID *uniqueTrashDirName = [[NSUUID alloc] initWithUUIDString:reportParentInTrash];

            expect(moveToTrash.destUrl.path).to.endWith(reportRelPath);
            expect(uniqueTrashDirName).toNot.beNil();

            assertWithTimeout(1.0, thatEventually(@(deleteFromTrash.isFinished)), isTrue());

            expect(deleteFromTrash.fileUrl).to.equal([trashDir URLByAppendingPathComponent:reportParentInTrash isDirectory:YES]);
        });

        it(@"cannot delete a report while importing", ^{

            NSURL *importingReportUrl = [reportsDir URLByAppendingPathComponent:@"importing.red"];
            [fileManager createFileAtPath:importingReportUrl.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
            TestImportProcess *process = [[redType enqueueImport] block];

            Report *importingReport = [store attemptToImportReportFromResource:importingReportUrl];

            assertWithTimeout(1.0, thatEventually(@(importingReport.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            expect(importingReport.importStatus).to.equal(ReportImportStatusImporting);

            [store deleteReport:importingReport];

            expect(importingReport.importStatus).to.equal(ReportImportStatusImporting);

            [process unblock];

            assertWithTimeout(1.0, thatEventually(@(importingReport.isImportFinished)), isTrue());
        });

        it(@"sends a notification when a report is removed from the reports list", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportRemoved on:store.notifications from:store withBlock:^(NSNotification *notification) {
                expect(store.reports).notTo.contain(singleResourceReport);
            }];
            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(1));

            ReceivedNotification *removed = observer.received.firstObject;

            expect(removed.notification.userInfo[@"report"]).to.beIdenticalTo(singleResourceReport);
        });

        it(@"can delete a failed download report with a remote url", ^{
            failure(@"unimplemented");
        });

        it(@"can delete a failed import report", ^{
            failure(@"unimplemented");
        });

    });

    describe(@"notifications", ^{

        it(@"works as expected", ^{
            NSMutableArray<NSNotification *> *notes = [NSMutableArray array];
            NSNotificationCenter *notifications = [[NSNotificationCenter alloc] init];
            [notifications addObserverForName:@"test.notification" object:self queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                [notes addObject:note];
            }];
            NotificationRecordingObserver *recorder = [NotificationRecordingObserver observe:@"test.notification" on:notifications from:self withBlock:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [notifications postNotificationName:@"test.notification" object:self];
            });
            
            assertWithTimeout(1.0, thatEventually(@(notes.count)), equalToUnsignedInteger(1));

            assertWithTimeout(1.0, thatEventually(@(recorder.received.count)), equalToUnsignedInteger(1));
        });

    });

});

SpecEnd
