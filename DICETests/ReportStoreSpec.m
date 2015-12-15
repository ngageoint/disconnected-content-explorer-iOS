
#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#import <OCMock/OCMock.h>

#import "ReportStore.h"
#import "ReportType.h"
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




@interface TestImportProcess : NSObject <ImportProcess>

@property (readonly) Report *report;
@property (readonly) NSArray *steps;
@property (weak) id<ImportDelegate> delegate;
@property (nonatomic) BOOL isBlocked;
@property (strong, nonatomic) void (^completeBlock)(void);

- (void)setReport:(Report *)report;
- (void)invokeCompleteBlock;

@end



@interface TestReportType : NSObject <ReportType>

@property (readonly) NSString *extension;
@property (readonly) TestImportProcess *nextImportProcess;

- (instancetype)initWithExtension:(NSString *)ext;

@end



@implementation TestImportProcess
{
    BOOL _isBlocked;
    NSCondition *_blockedCondition;
}

- (instancetype)init
{
    self = [super init];

    _isBlocked = NO;
    _blockedCondition = [[NSCondition alloc] init];
    __weak TestImportProcess *my = self;
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
        if (my.completeBlock) {
            [[NSRunLoop mainRunLoop] performSelector:@selector(invokeCompleteBlock) target:my argument:nil order:0 modes:@[NSDefaultRunLoopMode]];
        }
    }];
    [op2 addDependency:op1];
    _steps = @[op1, op2];

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

- (void)setReport:(Report *)report
{
    _report = report;
}

- (void)invokeCompleteBlock
{
    if (self.completeBlock) {
        self.completeBlock();
    }
    self.completeBlock = nil;
}

@end



@implementation TestReportType

- (instancetype)initWithExtension:(NSString *)ext
{
    if (!(self = [super init])) {
        return nil;
    }
    _nextImportProcess = [[TestImportProcess alloc] init];
    _extension = ext;
    return self;
}

- (BOOL)couldHandleFile:(NSURL *)reportPath
{
    return [reportPath.pathExtension isEqualToString:self.extension];
}

- (id<ImportProcess>)createImportProcessForReport:(Report *)report
{
    TestImportProcess *currentImport = self.nextImportProcess;
    [currentImport setReport:report];
    _nextImportProcess = [[TestImportProcess alloc] init];
    return currentImport;
}

@end




SpecBegin(ReportStore)

describe(@"ReportStore", ^{

    __block TestReportType *redType;
    __block TestReportType *blueType;
    __block NSFileManager *fileManager;
    __block ReportStore *store;
    __block id storeMock;

    NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice/reports"];

    beforeAll(^{

    });

    beforeEach(^{
        fileManager = OCMClassMock([NSFileManager class]);
        OCMStub([fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil])
            .andReturn(reportsDir);

        redType = [[TestReportType alloc] initWithExtension:@"red"];
        blueType = [[TestReportType alloc] initWithExtension:@"blue"];

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir fileManager:fileManager];
        store.reportTypes = @[
            redType,
            blueType
        ];
        storeMock = OCMPartialMock(store);
    });

    afterEach(^{
        [(id)fileManager stopMocking];
        fileManager = nil;
        [storeMock stopMocking];
        storeMock = nil;
    });

    afterAll(^{
        
    });

    describe(@"loadReports", ^{

        beforeEach(^{

        });

        it(@"finds the supported files in the reports directory", ^{
            [OCMStub([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil
                options:0
                error:nil]) andReturn:@[
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
            [OCMExpect([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                andReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            XCTestExpectation *redImported = [self expectationWithDescription:@"red imported"];
            XCTestExpectation *blueImported = [self expectationWithDescription:@"blue imported"];
            id<ImportProcess> redImport = redType.nextImportProcess;
            id<ImportProcess> blueImport = blueType.nextImportProcess;
            [[OCMStub([storeMock importDidFinishForImportProcess:redImport]) andForwardToRealObject] andDo:^(NSInvocation *invocation) {
                [redImported fulfill];
            }];
            [[OCMStub([storeMock importDidFinishForImportProcess:blueImport]) andForwardToRealObject] andDo:^(NSInvocation *invocation) {
                [blueImported fulfill];
            }];

            NSArray *reports = [store loadReports];

            [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
                if (error) {
                    failure(error.description);
                }
            }];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            [OCMExpect([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil
                options:0
                error:nil])
                andReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            reports = [store loadReports];

            OCMVerifyAll((id)fileManager);
            expect(reports.count).to.equal(1);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

        it(@"leaves reports whose path may not exist but are still importing", ^{
            [OCMExpect([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                andReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            TestImportProcess *blueImport = blueType.nextImportProcess;
            TestImportProcess *redImport = redType.nextImportProcess;
            redImport.isBlocked = YES;

            XCTestExpectation *blueImported = [self expectationWithDescription:@"blue import finished"];
            blueImport.completeBlock = ^{
                [blueImported fulfill];
            };

            NSArray<Report *> *reports = [store loadReports];

            [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
                if (error) {
                    failure(error.description);
                }
            }];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            expect(reports[0].isEnabled).to.equal(NO);
            expect(reports[1].isEnabled).to.equal(YES);

            [OCMExpect([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                andReturn:@[[reportsDir URLByAppendingPathComponent:@"report1.transformed"]]];

            reports = [store loadReports];
            
            OCMVerifyAll((id)fileManager);
            expect(reports.count).to.equal(1);
            expect(reports.firstObject.url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(reports.firstObject.isEnabled).to.equal(NO);

            XCTestExpectation *redImported = [self expectationWithDescription:@"red import finished"];
            redImport.completeBlock = ^{
                [redImported fulfill];
            };

            redImport.isBlocked = NO;

            [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
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
            [notifications addObserverForName:[ReportNotification reportAdded] object:store queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                [received addObject:note];
            }];

            [OCMStub([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil options:0 error:nil])
                andReturn:@[
                   [reportsDir URLByAppendingPathComponent:@"report1.red"],
                   [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            NSArray *reports = [store loadReports];

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

            id redMock = OCMPartialMock(redType);
            id blueMock = OCMPartialMock(blueType);

            [OCMStub([redMock createImportProcessForReport:anything()]) andForwardToRealObject];
            [[blueMock reject] createImportProcessForReport:anything()];
            TestImportProcess *import = redType.nextImportProcess;
            id importMock = OCMPartialMock(import);
            [OCMExpect([importMock steps]) andReturn:@[]];
            [OCMExpect([importMock setDelegate:store]) andForwardToRealObject];

            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            OCMVerify([redMock createImportProcessForReport:report]);
            OCMVerifyAll(importMock);

            [redMock stopMocking];
            [blueMock stopMocking];
            [importMock stopMocking];
        });

        it(@"returns nil if the report cannot be imported", ^{
            id redMock = OCMPartialMock(redType);
            id blueMock = OCMPartialMock(blueType);

            OCMStub([[redMock reject] createImportProcessForReport:anything()]);
            OCMStub([[blueMock reject] createImportProcessForReport:anything()]);

            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(report).to.beNil;

            [redMock stopMocking];
            [blueMock stopMocking];
        });

        it(@"adds the initial report to the report list", ^{
            
            XCTestExpectation *importFinished = [self expectationWithDescription:@"import finished"];
            TestImportProcess *import = redType.nextImportProcess;
            import.isBlocked = YES;
            import.completeBlock = ^{
                [importFinished fulfill];
            };

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

            __block NSNotification *received = nil;
            [notifications addObserverForName:[ReportNotification reportAdded] object:store queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                received = note;
            }];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            Report *receivedReport = received.userInfo[@"report"];

            expect(received.name).to.equal([ReportNotification reportAdded]);
            expect(receivedReport).to.beIdenticalTo(report);
        });

        it(@"does not start an import for a report file it is already importing", ^{

            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];

            XCTestExpectation *importFinished = [self expectationWithDescription:@"import finished"];
            TestImportProcess *import = redType.nextImportProcess;
            import.isBlocked = YES;
            import.completeBlock = ^{
                [importFinished fulfill];
            };

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            id redMock = OCMPartialMock(redType);
            OCMStub([[redMock reject] createImportProcessForReport:anything()]);

            Report *sameReport = [store attemptToImportReportFromResource:reportUrl];

            expect(sameReport).to.beIdenticalTo(report);
            OCMVerifyAll(redMock);
            [redMock stopMocking];

            import.isBlocked = NO;

            [self waitForExpectationsWithTimeout:1.0 handler:^(NSError * _Nullable error) {
                if (error) {
                    failure(error.description);
                }
            }];
        });

        it(@"does not add a report if it is already importing the report file", ^{
            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];

            TestImportProcess *import = redType.nextImportProcess;
            import.isBlocked = YES;

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            __block BOOL notified = NO;
            id<NSObject> observer = [[NSNotificationCenter defaultCenter] addObserverForName:[ReportNotification reportAdded] object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                notified = note.userInfo[@"report"] == report;
            }];

            [store attemptToImportReportFromResource:reportUrl];

            import.isBlocked = NO;
            [[NSNotificationCenter defaultCenter] removeObserver:observer name:[ReportNotification reportAdded] object:nil];

            expect(notified).to.equal(NO);
        });

        it(@"sends a notification when the import finishes", ^{
            failure(@"unimplemented");
        });

    });

});

SpecEnd
