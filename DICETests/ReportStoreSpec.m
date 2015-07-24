
#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#import "ReportStore.h"
#import "ReportType.h"


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

describe(@"ReportStore", ^{

    id<ReportType> redType = mockProtocol(@protocol(ReportType));
    id<ReportType> blueType = mockProtocol(@protocol(ReportType));

    [[given([redType couldHandleFile:nil]) withMatcher:endsWith(@".red")] willReturnBool:YES];
    [[given([redType couldHandleFile:nil]) withMatcher:isNot(endsWith(@".red"))] willReturnBool:NO];

    [[given([blueType couldHandleFile:nil]) withMatcher:endsWith(@".blue")] willReturnBool:YES];
    [[given([blueType couldHandleFile:nil]) withMatcher:isNot(endsWith(@".blue"))] willReturnBool:NO];

    NSFileManager *fileManager = mock([NSFileManager class]);

    NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice/reports"];

    __block ReportStore *store;

    beforeAll(^{

    });
    
    beforeEach(^{
        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir fileManager:fileManager];
        store.reportTypes = @[
            redType,
            blueType
        ];
    });

    describe(@"loadReports", ^{

        beforeEach(^{
            [given([fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil]) willReturn:reportsDir];
        });

        it(@"finds the supported files in the reports directory", ^{
            [given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil
                options:0
                error:nil])
                willReturn:@[
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
            [[given([fileManager contentsOfDirectoryAtURL:reportsDir
                includingPropertiesForKeys:nil
                options:0
                error:nil])
                willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report1.red"],
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]]
                willReturn:@[
                    [reportsDir URLByAppendingPathComponent:@"report2.blue"]
                ]];

            NSArray *reports = [store loadReports];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            ((Report *)reports[0]).isEnabled = YES;
            ((Report *)reports[1]).isEnabled = YES;

            [given([fileManager fileExistsAtPath:((Report *)reports[0]).url.path]) willReturnBool:NO];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

    });

    describe(@"attemptToImportReportFromResource", ^{

        it(@"imports a report with the capable ReportType", ^{
            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            [verify(redType) createImportProcessForReport:report];
            [verifyCount(blueType, never()) createImportProcessForReport:report];

            failure(@"verify interaction with ImportProcess");
        });

        it(@"returns nil if the report cannot be imported", ^{
            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(report).to.beNil;
            [verifyCount(redType, never()) createImportProcessForReport:report];
            [verifyCount(blueType, never()) createImportProcessForReport:report];
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

    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
