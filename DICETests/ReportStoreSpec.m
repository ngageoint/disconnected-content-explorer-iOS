
#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#import "ReportStore.h"
#import "ReportType.h"


SpecBegin(ReportStore)

describe(@"ReportStore", ^{

    id<ReportType> redType = mockProtocol(@protocol(ReportType));
    id<ReportType> blueType = mockProtocol(@protocol(ReportType));

    [[given([redType couldHandleFile:nil]) withMatcher:endsWith(@".red")] willReturnBool:YES];
    [[given([redType couldHandleFile:nil]) withMatcher:isNot(endsWith(@".red"))] willReturnBool:NO];

    [[given([blueType couldHandleFile:nil]) withMatcher:endsWith(@".blue")] willReturnBool:YES];
    [[given([blueType couldHandleFile:nil]) withMatcher:isNot(endsWith(@".blue"))] willReturnBool:NO];

    ReportStore *store = [[ReportStore alloc] init];
    store.reportTypes = @[
        redType,
        blueType
    ];

    beforeAll(^{

    });
    
    beforeEach(^{

    });

    describe(@"loadReports", ^{

        it(@"finds the supported files in the reports directory", ^{
            failure(@"unimplemented");
        });

        it(@"removes reports for files no longer in the reports directory", ^{
            failure(@"unimplemented");
        });

    });

    describe(@"attemptToImportReportFromResource", ^{

        it(@"imports a report with the capable ReportType", ^{
            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            [verify(redType) importReport:report];
            [verifyCount(blueType, never()) importReport:report];
        });

        it(@"returns nil if the report cannot be imported", ^{
            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(report).to.beNil;
            [verifyCount(redType, never()) importReport:report];
            [verifyCount(blueType, never()) importReport:report];
        });

        it(@"adds the initial report to the report list", ^{
            NSURL *url = [NSURL fileURLWithPath:@"/test/reports/report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(store.reports).to.contain(report);
        });

    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
