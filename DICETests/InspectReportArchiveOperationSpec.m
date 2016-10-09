//
//  InspectReportArchiveOperationSpec.m
//  DICE
//
//  Created by Robert St. John on 9/12/16.
//  Copyright 2016 mil.nga. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "DICEUtiExpert.h"
#import "ImportProcess+Internal.h"
#import "InspectReportArchiveOperation.h"
#import "Report.h"
#import "ReportType.h"
#import "TestDICEArchive.h"
#import "TestReportType.h"


#define entry(name, inArchive, extracted) [TestDICEArchiveEntry entryWithName:name sizeInArchive:inArchive sizeExtracted:extracted]


SpecBegin(InspectReportArchiveOperation)

describe(@"InspectReportArchiveOperation", ^{

    __block Report *report;
    __block DICEUtiExpert *utiExpert;
    __block NSFileManager *fileManager;
    __block id<ReportType> redType;
    __block id<ReportType> blueType;

    beforeAll(^{
    });

    beforeEach(^{
        report = [[Report alloc] init];
        utiExpert = [[DICEUtiExpert alloc] init];
        fileManager = mock([NSFileManager class]);
        redType = [[TestReportType alloc] initWithExtension:@"red" fileManager:fileManager];
        blueType = [[TestReportType alloc] initWithExtension:@"blue" fileManager:fileManager];
    });

    afterEach(^{
        stopMocking(fileManager);
    });

    afterAll(^{
    });

    it(@"finds the first matching report type", ^{
        NSURL *url = [NSURL fileURLWithPath:@"/dice/test.zip"];
        TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
            entry(@"index.red", 1, 1),
            entry(@"index.blue", 1, 1),
            entry(@"icon.png", 10, 40)
        ] archiveUrl:url archiveUti:kUTTypeZipArchive];
        id<ReportType> otherRedType = [[TestReportType alloc] initWithExtension:@"red" fileManager:fileManager];
        NSMutableArray *reportTypes = [@[redType, blueType, otherRedType] mutableCopy];
        InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:reportTypes utiExpert:utiExpert];
        [op start];

        expect(op.matchedReportType).to.beIdenticalTo(redType);

        [reportTypes exchangeObjectAtIndex:0 withObjectAtIndex:2];
        op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:reportTypes utiExpert:utiExpert];
        [op start];

        expect(op.matchedReportType).to.beIdenticalTo(otherRedType);

        [reportTypes exchangeObjectAtIndex:0 withObjectAtIndex:1];
        op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:reportTypes utiExpert:utiExpert];
        [op start];

        expect(op.matchedReportType).to.beIdenticalTo(blueType);
    });

    it(@"assigns the base directory when the archive has one", ^{
        NSURL *url = [NSURL fileURLWithPath:@"/dice/test.zip"];
        TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
            entry(@"test_base/index.red", 1, 1),
            entry(@"test_base/icon.png", 10, 40)
        ] archiveUrl:url archiveUti:kUTTypeZipArchive];
        InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:@[blueType, redType] utiExpert:utiExpert];
        [op start];

        expect(op.archiveBaseDir).to.equal(@"test_base");
        expect(op.matchedReportType).to.beIdenticalTo(redType);

        archive = [TestDICEArchive archiveWithEntries:@[
            entry(@"test_base/", 0, 0),
            entry(@"test_base/index.red", 1, 1),
            entry(@"test_base/icon.png", 10, 40),
            entry(@"test_base/stuff/", 0, 0),
            entry(@"test_base/stuff/info.txt", 5, 10)
        ] archiveUrl:url archiveUti:kUTTypeZipArchive];
        op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:@[blueType, redType] utiExpert:utiExpert];
        [op start];

        expect(op.archiveBaseDir).to.equal(@"test_base");
        expect(op.matchedReportType).to.beIdenticalTo(redType);

        archive = [TestDICEArchive archiveWithEntries:@[
            entry(@"test_base/extra/", 0, 0),
            entry(@"test_base/extra/index.red", 1, 1),
            entry(@"test_base/extra/icon.png", 10, 40),
            entry(@"test_base/extra/stuff/", 0, 0),
            entry(@"test_base/extra/stuff/info.txt", 5, 10)
        ] archiveUrl:url archiveUti:kUTTypeZipArchive];
        op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:@[blueType, redType] utiExpert:utiExpert];
        [op start];

        expect(op.archiveBaseDir).to.equal(@"test_base");
        expect(op.matchedReportType).to.beIdenticalTo(redType);
    });

    it(@"has a nil base directory when the archive more than one root entry", ^{
        NSURL *url = [NSURL fileURLWithPath:@"/dice/test.zip"];
        TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
            entry(@"test_base/", 0, 0),
            entry(@"test_base/random.thing", 1, 2),
            entry(@"index.red", 10, 40)
        ] archiveUrl:url archiveUti:kUTTypeZipArchive];
        InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:@[blueType, redType] utiExpert:utiExpert];
        [op start];

        expect(op.archiveBaseDir).to.beNil();
        expect(op.matchedReportType).to.beIdenticalTo(redType);
    });

    it(@"has a nil base directory when the archive has a single file entry", ^{
        NSURL *url = [NSURL fileURLWithPath:@"/dice/test.zip"];
        TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
            entry(@"index.red", 10, 40)
        ] archiveUrl:url archiveUti:kUTTypeZipArchive];
        InspectReportArchiveOperation *op = [[InspectReportArchiveOperation alloc]
            initWithReport:report reportArchive:archive candidateReportTypes:@[blueType, redType] utiExpert:utiExpert];
        [op start];

        expect(op.matchedReportType).to.beIdenticalTo(redType);
        expect(op.archiveBaseDir).to.beNil();
    });

});

SpecEnd
