//
//  ZippedHtmlImportProcessSpec.m
//  DICE
//
//  Created by Robert St. John on 7/31/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#import <OCMock/OCMock.h>

#import "HtmlReportType.h"
#import "UnzipOperation.h"
#import "FileOperations.h"
#import "SimpleFileManager.h"

#import "ZipFile.h"
#import "FileInZipInfo.h"




@interface TestUtil : NSObject

+ (ZipFile *)mockZipForReport:(Report *)report entryNames:(NSArray *)entryNames;

@end

@implementation TestUtil

+ (ZipFile *)mockZipForReport:(Report *)report entryNames:(NSArray *)entryNames
{
    NSMutableArray *entries = [NSMutableArray array];

    for (NSString *entryName in entryNames) {
        [entries addObject:[[FileInZipInfo alloc] initWithName:entryName length:0 level:ZipCompressionLevelDefault crypted:NO size:0 date:nil crc32:0]];
    }

    ZipFile *mockZipFile = mock([ZipFile class]);
    [given([mockZipFile fileName]) willReturn:report.url.path];
    [given([mockZipFile listFileInZipInfos]) willReturn:entries];

    return mockZipFile;
}

@end



SpecBegin(ZippedHtmlImportProcess)

describe(@"ZippedHtmlImportProcess", ^{

    id<SimpleFileManager> fileManager = OCMProtocolMock(@protocol(SimpleFileManager));
    NSURL * const reportsDir = [NSURL URLWithString:@"file:///apps/dice/Documents"];
    NSString * const reportFileName = @"test-ZippedHtmlImportProcess.zip";

    __block Report *initialReport;

    beforeAll(^{

    });
    
    beforeEach(^{
        initialReport = [[Report alloc] init];
        initialReport.url = [reportsDir URLByAppendingPathComponent:reportFileName];
        initialReport.title = reportFileName;
    });


    it(@"validates the zip file contents first", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[
            @"base/",
            @"base/index.html"
        ]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;

        expect(validateStep.zipFile).to.beIdenticalTo(zipFile);
    });

    it(@"is ready to unzip when the validation finishes successfully", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;
        UnzipOperation *unzipStep = import.steps[1];

        expect(unzipStep.dependencies).to.contain(validateStep);
        expect(unzipStep.ready).to.equal(NO);
        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });

        expect(unzipStep.ready).to.equal(YES);
    });

    it(@"cancels the unzip if the validation fails", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/readme.txt"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;
        UnzipOperation *unzipStep = import.steps[1];

        expect(unzipStep.dependencies).to.contain(validateStep);
        expect(unzipStep.ready).to.equal(NO);
        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });
        
        expect(validateStep.finished).to.equal(YES);
        expect(unzipStep.ready).to.equal(NO);
        expect(unzipStep.cancelled).to.equal(YES);
    });

    it(@"unzips to the reports dir when zip has base dir", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;
        UnzipOperation *unzipStep = import.steps[1];

        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });

        expect(unzipStep.destDir).to.equal(reportsDir);
    });

    it(@"creates and unzips to dir named after zip file when zip has no base dir", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;
        UnzipOperation *unzipStep = import.steps[1];
        MkdirOperation *mkdirStep = import.steps[2];

        NSString *baseDirName = [initialReport.url.lastPathComponent stringByDeletingPathExtension];
        NSURL *destDir = [reportsDir URLByAppendingPathComponent:baseDirName];

        OCMStub([fileManager mkdir:destDir]).andReturn(YES);

        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });

        OCMVerify([fileManager mkdir:destDir]);
        expect(unzipStep.destDir).to.equal(destDir);
    });

    it(@"moves the extracted content to the reports directory", ^{
        failure(@"unimplemented");
    });

    it(@"unzips the file to a temporary directory", ^{
        NSString *uuid = [[NSUUID UUID] UUIDString];
        NSString *tempDirName = [@"temp-" stringByAppendingString:uuid];
        NSURL *tempDir = [reportsDir URLByAppendingPathComponent:tempDirName];

        [given([fileManager createTempDir]) willReturn:tempDir];

        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        id<ImportProcess> import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];
        UnzipOperation *unzipStep = import.steps[1];

        expect(unzipStep.zipFile).to.equal(initialReport.url);
        expect(unzipStep.destDir).to.equal(tempDir);

        failure(@"unimplemented - unnecessary?  could make concurrency issues simpler");
    });

    it(@"deletes the zip file after unzipping successfully", ^{
        Report *report = [[Report alloc] init];
        report.url = [reportsDir URLByAppendingPathComponent:@"success.zip"];

        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        id<ImportProcess> import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        DeleteFileOperation *deleteStep = import.steps.lastObject;

        expect(deleteStep.fileUrl).to.equal(report.url);
    });

    it(@"leaves the zip file if an error occurs", ^{
        failure(@"unimplemented");
    });

    it(@"reports unzip progress updates", ^{
        failure(@"unimplemented");
    });

    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
