
#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ImportProcess+Internal.h"
#import "ReportStore.h"
#import "NSOperation+Blockable.h"
#import "NotificationRecordingObserver.h"


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



@interface ReportStoreSpec_ImportProcess : ImportProcess

- (instancetype)initWithReport:(Report *)report NS_DESIGNATED_INITIALIZER;
- (instancetype)block;
- (instancetype)unblock;

@end



@interface ReportStoreSpec_ReportType : NSObject <ReportType>

@property (readonly) NSString *extension;
@property (copy) ReportStoreSpec_ImportProcess * (^nextImportProcess)(Report *);

- (instancetype)initWithExtension:(NSString *)ext NS_DESIGNATED_INITIALIZER;

@end



@implementation ReportStoreSpec_ImportProcess

- (instancetype)init
{
    self = [self initWithReport:nil];
    return nil;
}

- (instancetype)initWithReport:(Report *)report
{
    self = [super initWithReport:report];

    ReportStoreSpec_ImportProcess *my = self;
    NSBlockOperation *op1 = [NSBlockOperation blockOperationWithBlock:^{
        my.report.summary = @"op1:finished";
        if (my.delegate) {
            [my.delegate reportWasUpdatedByImportProcess:my];
        }
    }];
    NSBlockOperation *op2 = [NSBlockOperation blockOperationWithBlock:^{
        my.report.isEnabled = YES;
        my.report.title = @"Test Report";
        my.report.summary = @"It's a test";
        if (my.delegate) {
            [my.delegate reportWasUpdatedByImportProcess:my];
            [my.delegate importDidFinishForImportProcess:my];
        }
    }];
    [op2 addDependency:op1];
    self.steps = @[op1, op2];

    return self;
}

- (instancetype)cancelAll
{
    self.steps = @[];
    return self;
}

- (instancetype)block
{
    [self.steps.firstObject block];
    return self;
}

- (instancetype)unblock
{
    [self.steps.firstObject unblock];
    return self;
}

@end



@implementation ReportStoreSpec_ReportType

- (instancetype)init
{
    return [self initWithExtension:nil];
}

- (instancetype)initWithExtension:(NSString *)ext
{
    if (!ext) {
        [NSException raise:NSInvalidArgumentException format:@"ext is nil"];
    }

    self = [super init];

    _extension = ext;

    return self;
}

- (BOOL)couldHandleFile:(NSURL *)reportPath
{
    return [reportPath.pathExtension isEqualToString:self.extension];
}

- (ImportProcess *)createProcessToImportReport:(Report *)report toDir:(NSURL *)destDir
{
    if (self.nextImportProcess) {
        return self.nextImportProcess(report);
    }
    return [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
}

@end




SpecBegin(ReportStore)

describe(@"ReportStore", ^{

    __block ReportStoreSpec_ReportType *redType;
    __block ReportStoreSpec_ReportType *blueType;
    __block NSFileManager *fileManager;
    __block NSOperationQueue *importQueue;
    __block ReportStore *store;

    NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice/reports"];

    beforeAll(^{

    });

    beforeEach(^{
        fileManager = mock([NSFileManager class]);
        [given([fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil])
            willReturn:reportsDir];

        importQueue = [[NSOperationQueue alloc] init];

        redType = [[ReportStoreSpec_ReportType alloc] initWithExtension:@"red"];
        blueType = [[ReportStoreSpec_ReportType alloc] initWithExtension:@"blue"];

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir fileManager:fileManager importQueue:importQueue];
        store.reportTypes = @[
            redType,
            blueType
        ];
    });

    afterEach(^{
        [importQueue waitUntilAllOperationsAreFinished];
        stopMocking(fileManager);
        fileManager = nil;
    });

    afterAll(^{
        
    });

    describe(@"loadReports", ^{

        beforeEach(^{

        });

        it(@"finds the supported files in the reports directory", ^{
            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil
                options:0
                error:nil]) willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"],
                    [reportsDir URLByAppendingPathComponent:@"something.else"]
                ]];

            NSArray *reports = [store loadReports];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

        it(@"removes reports with path that does not exist and not importing", ^{
            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };
            blueType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };

            NSArray *reports = [store loadReports];

            [importQueue waitUntilAllOperationsAreFinished];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil
                options:0
                error:nil])
                willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

        // TODO: don't care for now
        xit(@"leaves imported and importing reports in the same order", ^{
            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"],
                    [reportsDir URLByAppendingPathComponent:@"report3.red"]
                ]];

            __block Report *blueReport;
            blueType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                blueReport = report;
                return [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };

            __block Report *redReport;
            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                redReport = report;
                return [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };

            NSArray<Report *> *reports = [NSArray arrayWithArray:[store loadReports]];

            NSUInteger bluePos = [reports indexOfObject:blueReport];

            expect(reports.count).to.equal(3);

            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report11.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"],
                    [reportsDir URLByAppendingPathComponent:@"report3.red"]
                ]];

            reports = [NSArray arrayWithArray:[store loadReports]];
            [importQueue waitUntilAllOperationsAreFinished];

            failure(@"unimplemented");
        });

        it(@"leaves reports whose path may not exist but are still importing", ^{
            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            __block ReportStoreSpec_ImportProcess *blueImport;
            blueType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return blueImport = [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };
            __block ReportStoreSpec_ImportProcess *redImport;
            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return redImport = [[[ReportStoreSpec_ImportProcess alloc] initWithReport:report] block];
            };

            NSArray<Report *> *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(blueImport.steps), everyItem(hasProperty(@"isFinished", isTrue())));

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            expect([reports[0] isEnabled]).to.equal(NO);
            expect([reports[1] isEnabled]).to.equal(YES);

            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                willReturn:@[[reportsDir URLByAppendingPathComponent:@"report1.transformed"]]];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports.firstObject).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports.firstObject).isEnabled).to.equal(NO);

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(redImport.steps), everyItem(hasProperty(@"isFinished", isTrue())));

            expect(store.reports.count).to.equal(1);
            expect(((Report *)store.reports.firstObject).url.lastPathComponent).to.equal(@"report1.red");
            expect(((Report *)store.reports.firstObject).isEnabled).to.equal(YES);
        });

        it(@"sends notifications about added reports", ^{
            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                willReturn:@[
                   [reportsDir URLByAppendingPathComponent:@"report1.red"],
                   [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return [[[ReportStoreSpec_ImportProcess alloc] initWithReport:report] cancelAll];
            };
            blueType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return [[[ReportStoreSpec_ImportProcess alloc] initWithReport:report] cancelAll];
            };

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(2));

            [observer.received enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSNotification *note = [obj notification];
                Report *report = note.userInfo[@"report"];

                expect(note.name).to.equal([ReportNotification reportAdded]);
                expect(report).to.beIdenticalTo(reports[idx]);
            }];

            [notifications removeObserver:observer];
        });

    });

    describe(@"attemptToImportReportFromResource", ^{

        it(@"imports a report with the capable ReportType", ^{

            __block ReportStoreSpec_ImportProcess *redImport;
            __block ReportStoreSpec_ImportProcess *blueImport;

            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return redImport = [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };
            blueType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return blueImport = [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            [importQueue waitUntilAllOperationsAreFinished];

            expect(redImport).toNot.beNil;
            expect(blueImport).to.beNil;
        });

        it(@"returns nil if the report cannot be imported", ^{
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(importQueue.operationCount).to.equal(0);

            [importQueue waitUntilAllOperationsAreFinished];

            expect(report).to.beNil;
        });

        it(@"adds the initial report to the report list", ^{
            __block ReportStoreSpec_ImportProcess *import;
            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return import = [[[ReportStoreSpec_ImportProcess alloc] initWithReport:report] block];
            };

            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(store.reports).to.contain(report);
            expect(report.reportID).to.equal(report.url.path);
            expect(report.title).to.equal(report.url.lastPathComponent);
            expect(report.summary).to.equal(@"Importing...");
            expect(report.error).to.beNil;
            expect(report.isEnabled).to.equal(NO);

            [import unblock];

            [importQueue waitUntilAllOperationsAreFinished];
        });

        it(@"sends a notification about adding the report", ^{
            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                return [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            [importQueue waitUntilAllOperationsAreFinished];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            ReceivedNotification *received = observer.received.firstObject;
            Report *receivedReport = received.notification.userInfo[@"report"];

            expect(received.notification.name).to.equal([ReportNotification reportAdded]);
            expect(receivedReport).to.beIdenticalTo(report);

            [notifications removeObserver:observer];
        });

        it(@"does not start an import for a report file it is already importing", ^{
            __block ReportStoreSpec_ImportProcess *import;
            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                if (import) {
                    [NSException raise:NSInternalInconsistencyException format:@"more than one import process created"];
                }
                return import = [[[ReportStoreSpec_ImportProcess alloc] initWithReport:report] block];
            };

            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];
            Report *report = [store attemptToImportReportFromResource:reportUrl];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(report);
            expect(store.reports.firstObject).to.beIdenticalTo(notificationReport);
            expect(store.reports.count).to.equal(1);

            notificationReport = nil;
            [observer.received removeAllObjects];

            Report *sameReport = [store attemptToImportReportFromResource:reportUrl];

            [import unblock];

            [importQueue waitUntilAllOperationsAreFinished];

            [notifications removeObserver:observer];

            expect(sameReport).to.beIdenticalTo(report);
            expect(store.reports.count).to.equal(1);
            expect(observer.received.count).to.equal(0);
        });

        it(@"enables the report when the import finishes", ^{
            Report *report = mock([Report class]);
            ReportStoreSpec_ImportProcess *import = [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];

            __block BOOL enabledOnMainThread = NO;
            [givenVoid([report setIsEnabled:YES]) willDo:^id(NSInvocation *invocation) {
                BOOL enabled = NO;
                [invocation getArgument:&enabled atIndex:2];
                enabledOnMainThread = enabled && [NSThread isMainThread];
                return nil;
            }];

            [store importDidFinishForImportProcess:import];

            assertWithTimeout(1.0, thatEventually(@(enabledOnMainThread)), isTrue());
        });

        it(@"sends a notification when the import finishes", ^{
            __block ReportStoreSpec_ImportProcess *import;
            redType.nextImportProcess = ^ReportStoreSpec_ImportProcess *(Report *report) {
                if (import) {
                    [NSException raise:NSInternalInconsistencyException format:@"more than one import process created"];
                }
                return import = [[ReportStoreSpec_ImportProcess alloc] initWithReport:report];
            };

            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportImportFinished] on:notifications from:store withBlock:nil];

            Report *importReport = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            [importQueue waitUntilAllOperationsAreFinished];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            [notifications removeObserver:observer];

            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(importReport);
        });

    });

});

SpecEnd
