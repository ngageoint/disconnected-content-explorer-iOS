
#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#import "ImportProcess+Internal.h"
#import "ReportStore.h"
#import "ReportAPI.h"


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


@interface ImportProcess ()

@property (readwrite) Report *report;

@end


@interface ReportStoreSpec_ImportProcess : ImportProcess

@property (nonatomic) BOOL isBlocked;
@property (weak, readonly) XCTest *test;
@property (readonly) NSString *testDescription;

- (instancetype)initWithTest:(XCTest *)test NS_DESIGNATED_INITIALIZER;
- (instancetype)setFinishExpectationForTest:(XCTestCase *)test;
- (instancetype)setFinishBlock:(void (^)(void))block;

- (NSOperation *)nextStep;

@end





@interface ReportStoreSpec_ReportType : NSObject <ReportType>

@property (readonly) NSString *extension;
@property ReportStoreSpec_ImportProcess *nextImportProcess;
@property (weak, readonly) XCTest *test;
@property (readonly) NSString *testDescription;

- (instancetype)initWithExtension:(NSString *)ext test:(XCTest *)test NS_DESIGNATED_INITIALIZER;

@end



@implementation ReportStoreSpec_ImportProcess
{
    BOOL _isBlocked;
    NSCondition *_blockedCondition;
    void (^_finishBlock)(void);
    XCTestExpectation *_finishedExpectation;
    NSUInteger _stepCursor;
}

- (instancetype)init
{
    return [self initWithTest:nil];
}

- (instancetype)initWithTest:(XCTest *)test
{
    if (!test) {
        [NSException raise:NSInvalidArgumentException format:@"test is nil"];
    }

    self = [super init];

    _stepCursor = 0;
    _test = test;
    _isBlocked = NO;
    _blockedCondition = [[NSCondition alloc] init];
    __weak ReportStoreSpec_ImportProcess *my = self;
    NSBlockOperation *op1 = [NSBlockOperation blockOperationWithBlock:^{
        [_blockedCondition lock];
        if (_isBlocked) {
            if (my.delegate) {
                [my.delegate reportWasUpdatedByImportProcess:my];
            }
        }
        while (_isBlocked) {
            [_blockedCondition wait];
        };
        [_blockedCondition unlock];

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
        if (_finishBlock) {
            [[NSRunLoop mainRunLoop] performSelector:@selector(invokeFinishBlock) target:my argument:nil order:0 modes:@[NSDefaultRunLoopMode]];
        }
        if (_finishedExpectation) {
            [_finishedExpectation fulfill];
        }
    }];
    [op2 addDependency:op1];
    self.steps = @[op1, op2];

    return self;
}

- (NSString *)testDescription
{
    return self.test.description;
}

- (instancetype)noop
{
    for (NSBlockOperation *step in self.steps) {
        [step cancel];
    }
    self.steps = @[];
    return self;
}

- (BOOL)isBlocked
{
    BOOL x = NO;
    [_blockedCondition lock];
    x = _isBlocked;
    [_blockedCondition unlock];
    return x;
}

- (void)setIsBlocked:(BOOL)isBlocked
{
    [_blockedCondition lock];
    _isBlocked = isBlocked;
    [_blockedCondition signal];
    [_blockedCondition unlock];
}

- (instancetype)setFinishBlock:(void (^)(void))block
{
    _finishBlock = block;
    return self;
}

- (void)invokeFinishBlock
{
    if (_finishBlock) {
        _finishBlock();
    }
    _finishBlock = nil;
}

- (instancetype)setFinishExpectationForTest:(XCTestCase *)test
{
    if (_finishedExpectation) {
        [NSException raise:NSInternalInconsistencyException format:@"expectation already set"];
    }
    _finishedExpectation = [test expectationWithDescription:@"import finished"];
    return self;
}

- (NSOperation *)nextStep
{
    if (_stepCursor >= self.steps.count) {
        return nil;
    }
    return (NSOperation *)self.steps[_stepCursor++];
}

@end



@implementation ReportStoreSpec_ReportType

- (instancetype)init
{
    return [self initWithExtension:nil test:nil];
}

- (instancetype)initWithExtension:(NSString *)ext test:(XCTest *)test
{
    if (!ext) {
        [NSException raise:NSInvalidArgumentException format:@"ext is nil"];
    }
    if (!test) {
        [NSException raise:NSInvalidArgumentException format:@"test is nil"];
    }
    self = [super init];
    _test = test;
    _nextImportProcess = [[ReportStoreSpec_ImportProcess alloc] initWithTest:test];
    _extension = ext;
    return self;
}

- (NSString *)testDescription
{
    return self.test.description;
}

- (BOOL)couldHandleFile:(NSURL *)reportPath
{
    return [reportPath.pathExtension isEqualToString:self.extension];
}

- (ImportProcess *)createProcessToImportReport:(Report *)report toDir:(NSURL *)destDir
{
    ReportStoreSpec_ImportProcess *currentImport = self.nextImportProcess;
    currentImport.report = report;
    _nextImportProcess = [[ReportStoreSpec_ImportProcess alloc] initWithTest:self.test];
    return currentImport;
}

@end




SpecBegin(ReportStore)

describe(@"ReportStore", ^{

    __block ReportStoreSpec_ReportType *redType;
    __block ReportStoreSpec_ReportType *blueType;
    __block NSFileManager *fileManager;
    __block ReportStore *store;
    __block id storeMock;

    NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice/reports"];

    beforeAll(^{

    });

    beforeEach(^{
        fileManager = mock([NSFileManager class]);
        [given([fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil])
            willReturn:reportsDir];

        redType = [[ReportStoreSpec_ReportType alloc] initWithExtension:@"red" test:self];
        blueType = [[ReportStoreSpec_ReportType alloc] initWithExtension:@"blue" test:self];

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir fileManager:fileManager];
        store.reportTypes = @[
            redType,
            blueType
        ];
        storeMock = (store);
    });

    afterEach(^{
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

            [redType.nextImportProcess setFinishExpectationForTest:self];
            [blueType.nextImportProcess setFinishExpectationForTest:self];

            NSArray *reports = [store loadReports];

            [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
                if (error) {
                    failure(error.description);
                }
            }];

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

        it(@"leaves reports whose path may not exist but are still importing", ^{
            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            [blueType.nextImportProcess setFinishExpectationForTest:self];
            ReportStoreSpec_ImportProcess *redImport = redType.nextImportProcess;
            redImport.isBlocked = YES;

            NSArray<Report *> *reports = [store loadReports];

            [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
                if (error) {
                    failure(error.description);
                }
            }];

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
            expect(reports.firstObject.url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(reports.firstObject.isEnabled).to.equal(NO);

            [redImport setFinishExpectationForTest:self];

            redImport.isBlocked = NO;

            [self waitForExpectationsWithTimeout:1.0 handler:^(NSError * _Nullable error) {
                if (error) {
                    failure(error.description);
                }
            }];

            expect(store.reports.count).to.equal(1);
            expect(store.reports.firstObject.url.lastPathComponent).to.equal(@"report1.red");
            expect(store.reports.firstObject.isEnabled).to.equal(YES);
        });

        it(@"sends notifications about added reports", ^{
            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];

            NSMutableArray *received = [NSMutableArray array];
            id observer = [notifications addObserverForName:[ReportNotification reportAdded] object:store queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                [received addObject:note];
            }];

            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                willReturn:@[
                   [reportsDir URLByAppendingPathComponent:@"report1.red"],
                   [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            [redType.nextImportProcess noop];
            [blueType.nextImportProcess noop];

            NSArray *reports = [store loadReports];

            [notifications removeObserver:observer];

            expect(received.count).to.equal(2);

            [received enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSNotification *note = obj;
                Report *report = note.userInfo[@"report"];
                
                expect(note.name).to.equal([ReportNotification reportAdded]);
                expect(report).to.beIdenticalTo(reports[idx]);
            }];
        });

    });

    describe(@"attemptToImportReportFromResource", ^{

        it(@"imports a report with the capable ReportType", ^{
            ReportStoreSpec_ImportProcess *targetImport = [[[ReportStoreSpec_ImportProcess alloc] initWithTest:self] setFinishExpectationForTest:self];
            id<ReportType> targetType = mockProtocol(@protocol(ReportType));
            [given([targetType couldHandleFile:endsWith(@".red")]) willReturnBool:YES];
            [given([targetType couldHandleFile:isNot(endsWith(@".red"))]) willReturnBool:NO];
            [given([targetType createProcessToImportReport:anything() toDir:reportsDir]) willReturn:targetImport];
            id<ReportType> otherType = mockProtocol(@protocol(ReportType));
            [given([otherType createProcessToImportReport:anything() toDir:reportsDir]) willDo:^id(NSInvocation *invocation) {
                failure(@"wrong report type");
                return nil;
            }];

            ReportStore *testStore = [[ReportStore alloc] initWithReportsDir:reportsDir fileManager:fileManager];
            testStore.reportTypes = @[otherType, targetType];

            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.red"];
            Report *report = [testStore attemptToImportReportFromResource:url];

            [self waitForExpectationsWithTimeout:1.0 handler:^(NSError * _Nullable error) {
                if (error) {
                    failure(error.description);
                }
            }];

            [verify(targetType) createProcessToImportReport:report toDir:reportsDir];
        });

        it(@"returns nil if the report cannot be imported", ^{
            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(report).to.beNil;
        });

        it(@"adds the initial report to the report list", ^{
            ReportStoreSpec_ImportProcess *import = [redType.nextImportProcess setFinishExpectationForTest:self];
            import.isBlocked = YES;

            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(store.reports).to.contain(report);
            expect(report.reportID).to.equal(report.url.path);
            expect(report.title).to.equal(report.url.lastPathComponent);
            expect(report.summary).to.equal(@"Importing...");
            expect(report.error).to.beNil;
            expect(report.isEnabled).to.equal(NO);

            import.isBlocked = NO;

            [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
                if (error) {
                    failure(error.description);
                }
            }];
        });

        it(@"sends a notification about adding the report", ^{
            NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];

            XCTestExpectation *notificationReceived = [self expectationWithDescription:@"notification received"];

            __block NSNotification *received = nil;
            id observer = [notifications addObserverForName:[ReportNotification reportAdded] object:store queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                [notificationReceived fulfill];
                received = note;
            }];

            [redType.nextImportProcess setFinishExpectationForTest:self];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            [self waitForExpectationsWithTimeout:1.0 handler:^(NSError * _Nullable error) {
                [notifications removeObserver:observer];
                if (error) {
                    failure(error.description);
                }
            }];

            Report *receivedReport = received.userInfo[@"report"];

            expect(received.name).to.equal([ReportNotification reportAdded]);
            expect(receivedReport).to.beIdenticalTo(report);
        });

        it(@"does not start an import for a report file it is already importing", ^{
            ReportStoreSpec_ImportProcess *import = [[[ReportStoreSpec_ImportProcess alloc] initWithTest:self] setFinishExpectationForTest:self];
            import.isBlocked = YES;

            id<ReportType> type = mockProtocol(@protocol(ReportType));
            [[given([type couldHandleFile:endsWith(@"report1.red")]) willReturnBool:YES] willReturnBool:YES];
            [given([type createProcessToImportReport:anything() toDir:reportsDir]) willDo:^id(NSInvocation *invocation) {
                Report *report;
                [invocation getArgument:&report atIndex:2];
                import.report = report;
                return import;
            }];

            __block Report *notificationReport;
            id<NSObject> observer = [[NSNotificationCenter defaultCenter] addObserverForName:[ReportNotification reportAdded] object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                notificationReport = note.userInfo[@"report"];
            }];

            ReportStore *testStore = [[ReportStore alloc] initWithReportsDir:reportsDir fileManager:fileManager];
            testStore.reportTypes = @[type];

            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];
            Report *report = [testStore attemptToImportReportFromResource:reportUrl];

            expect(testStore.reports.count).to.equal(1);
            expect(notificationReport).to.beIdenticalTo(report);

            notificationReport = nil;
            Report *sameReport = [testStore attemptToImportReportFromResource:reportUrl];

            expect(sameReport).to.beIdenticalTo(report);
            expect(testStore.reports.count).to.equal(1);
            expect(notificationReport).to.beNil;
            [verifyCount(type, times(1)) createProcessToImportReport:anything() toDir:reportsDir];

            import.isBlocked = NO;

            [self waitForExpectationsWithTimeout:1.0 handler:^(NSError * _Nullable error) {
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                if (error) {
                    failure(error.description);
                }
            }];
        });

        it(@"sends a notification when the import finishes", ^{
            failure(@"unimplemented");
        });

    });

});

SpecEnd