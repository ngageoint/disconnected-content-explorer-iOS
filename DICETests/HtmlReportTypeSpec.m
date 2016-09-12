//
//  ReportTypeTests.m
//  DICE
//
//  Created by Robert St. John on 5/22/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//


#import <Specta/Specta.h>
#import <Expecta/Expecta.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ResourceTypes.h"
#import "HtmlReportType.h"
#import "UnzipOperation.h"
#import "ZippedHtmlImportProcess.h"
#import "ExplodedHtmlImportProcess.h"



SpecBegin(HtmlReportType)

describe(@"HtmlReportType", ^{

    NSURL * const reportsDir = [NSURL fileURLWithPath:@"/test/reports/"];

    __block NSFileManager *fileManager;
    __block HtmlReportType *htmlReportType;

    beforeAll(^{

    });

    beforeEach(^{
        fileManager = mock([NSFileManager class]);
        htmlReportType = [[HtmlReportType alloc] initWithFileManager:fileManager];
    });

    afterEach(^{
        stopMocking(fileManager);
    });


    it(@"could handle a directory if it contains index.html", ^{
        NSURL *dirPath = [reportsDir URLByAppendingPathComponent:@"test_report"];
        NSURL *indexPath = [dirPath URLByAppendingPathComponent:@"index.html"];

        [given([fileManager attributesOfItemAtPath:dirPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [given([fileManager attributesOfItemAtPath:indexPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldImportFromPath:dirPath]).to.equal(YES);
    });

    it(@"could not handle a directory without index.html", ^{
        NSURL *dirPath = [reportsDir URLByAppendingPathComponent:@"test_reports"];
        NSURL *indexPath = [reportsDir URLByAppendingPathComponent:@"index.html"];

        [given([fileManager attributesOfItemAtPath:dirPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [given([fileManager attributesOfItemAtPath:indexPath.path error:nil]) willReturn:nil];

        expect([htmlReportType couldImportFromPath:dirPath]).to.equal(NO);
    });

    it(@"could not handle a directory when index.html is a directory", ^{
        NSURL *dirPath = [reportsDir URLByAppendingPathComponent:@"test_reports"];
        NSURL *indexPath = [reportsDir URLByAppendingPathComponent:@"index.html"];

        [given([fileManager attributesOfItemAtPath:dirPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [given([fileManager attributesOfItemAtPath:indexPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];

        expect([htmlReportType couldImportFromPath:dirPath]).to.equal(NO);
    });

    it(@"could not handle a zip file", ^{
        NSURL *zipPath = [reportsDir URLByAppendingPathComponent:@"test_report.zip"];

        [given([fileManager attributesOfItemAtPath:zipPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldImportFromPath:zipPath]).to.equal(NO);
    });

    it(@"could handle an html file", ^{
        NSURL *htmlPath = [reportsDir URLByAppendingPathComponent:@"test_report.html"];

        [given([fileManager attributesOfItemAtPath:htmlPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldImportFromPath:htmlPath]).to.equal(YES);
    });

    it(@"could not handle something else", ^{
        NSURL *filePath = [reportsDir URLByAppendingPathComponent:@"test_report.txt"];

        [given([fileManager attributesOfItemAtPath:filePath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldImportFromPath:filePath]).to.equal(NO);
    });

    it(@"could not handle a non-regular file or non-directory", ^{
        NSURL *filePath = [reportsDir URLByAppendingPathComponent:@"i_dunno"];

        [given([fileManager attributesOfItemAtPath:filePath.path error:nil]) willReturn:@{NSFileType: NSFileTypeSocket}];

        expect([htmlReportType couldImportFromPath:filePath]).to.equal(NO);
    });

    it(@"creates an exploded html report import process for a directory report url", ^{
        NSURL *reportPath = [reportsDir URLByAppendingPathComponent:@"test_report" isDirectory:YES];
        Report *report = [[Report alloc] init];
        report.url = reportPath;
        NSString *indexPath = [reportPath.path stringByAppendingPathComponent:@"index.html"];
        [given([fileManager attributesOfItemAtPath:reportPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [given([fileManager attributesOfItemAtPath:indexPath error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];
        ImportProcess *import = [htmlReportType createProcessToImportReport:report toDir:reportsDir];
        expect(import).to.beInstanceOf([ExplodedHtmlImportProcess class]);
    });

    it(@"creates an exploded html report import process for an html file report url", ^{
        NSURL *reportPath = [reportsDir URLByAppendingPathComponent:@"test_report.html" isDirectory:NO];
        Report *report = [[Report alloc] init];
        report.url = reportPath;
        [given([fileManager attributesOfItemAtPath:reportPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];
        ImportProcess *import = [htmlReportType createProcessToImportReport:report toDir:reportsDir];
        expect(import).to.beInstanceOf([ExplodedHtmlImportProcess class]);
    });

    it(@"creates a zipped html report import process for a zip file report url", ^{
        NSBundle *bundle = [NSBundle bundleForClass:[HtmlReportTypeSpec class]];
        NSString *path = [bundle pathForResource:@"test_base_dir" ofType:@"zip"];
        NSURL *reportPath = [NSURL fileURLWithPath:path];
        Report *report = [[Report alloc] init];
        report.url = reportPath;
        [given([fileManager attributesOfItemAtPath:reportPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];
        ImportProcess *import = [htmlReportType createProcessToImportReport:report toDir:reportsDir];
        expect(import).to.beInstanceOf([ZippedHtmlImportProcess class]);
    });

});

SpecEnd
