
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




@interface TestReportType : NSObject <ReportType>

@property (readonly) NSString *extension;
@property (readonly) id<ImportProcess> nextImportProcess;

- (instancetype)initWithExtension:(NSString *)ext;

@end




@implementation TestReportType

- (instancetype)initWithExtension:(NSString *)ext
{
    if (!(self = [super init])) {
        return nil;
    }
    _nextImportProcess = OCMProtocolMock(@protocol(ImportProcess));
    _extension = ext;
    return self;
}

- (BOOL)couldHandleFile:(NSURL *)reportPath
{
    return [reportPath.pathExtension isEqualToString:self.extension];
}

- (id<ImportProcess>)createImportProcessForReport:(Report *)report
{
    id currentImport = self.nextImportProcess;
    _nextImportProcess = OCMProtocolMock(@protocol(ImportProcess));
    return currentImport;
}

@end




SpecBegin(ReportStore)

describe(@"ReportStore", ^{

    __block TestReportType *redType = [[TestReportType alloc] initWithExtension:@"red"];
    __block TestReportType *blueType = [[TestReportType alloc] initWithExtension:@"blue"];

    __block NSFileManager *fileManager;
    __block ReportStore *store;

    NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice/reports"];

    beforeAll(^{

    });

    beforeEach(^{
        fileManager = OCMClassMock([NSFileManager class]);
        OCMStub([fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil])
            .andReturn(reportsDir);

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir fileManager:fileManager];
        store.reportTypes = @[
            redType,
            blueType
        ];
    });

    afterEach(^{
        [(id)fileManager stopMocking];
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

        it(@"removes enabled reports for files no longer in the reports directory", ^{
            [OCMExpect([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil
                options:0
                error:nil])
                andReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            NSArray *reports = [store loadReports];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            ((Report *)reports[0]).isEnabled = YES;
            ((Report *)reports[1]).isEnabled = YES;

            [OCMExpect([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil
                options:0
                error:nil])
                andReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            OCMStub([fileManager fileExistsAtPath:((Report *)reports[0]).url.path]).andReturn(NO);

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
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

            OCMStub([redMock createImportProcessForReport:anything()]).andForwardToRealObject;
            [[blueMock reject] createImportProcessForReport:anything()];
            id<ImportProcess> import = redType.nextImportProcess;
            OCMExpect([import steps]);
            OCMExpect([import setDelegate:store]);

            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            OCMVerify([redMock createImportProcessForReport:report]);
            OCMVerifyAll((id)import);

            [redMock stopMocking];
            [blueMock stopMocking];
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
            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(store.reports).to.contain(report);
            expect(report.reportID).to.equal(report.url.path);
            expect(report.title).to.equal(report.url.lastPathComponent);
            expect(report.summary).to.equal(@"Importing...");
            expect(report.error).to.beNil;
            expect(report.isEnabled).to.equal(NO);
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

    });

});

SpecEnd
