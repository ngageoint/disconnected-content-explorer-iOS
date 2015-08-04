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

id mockFinishOp(NSOperation *op) {
    id mock = OCMPartialMock(op);
    OCMStub([mock main]);
    [op start];
    return mock;
}


SpecBegin(ZippedHtmlImportProcess)

describe(@"ZippedHtmlImportProcess", ^{

    id<SimpleFileManager> fileManager = OCMProtocolMock(@protocol(SimpleFileManager));
    NSURL * const reportsDir = [NSURL URLWithString:@"file:///apps/dice/Documents"];
    NSString * const reportFileName = @"ZippedHtmlImportProcessSpec.zip";

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

    it(@"makes the base dir when the validation finishes successfully", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"icon.gif", @"index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;
        MkdirOperation *makeDestDirStep = import.steps[1];

        expect(makeDestDirStep.dependencies).to.contain(validateStep);
        expect(makeDestDirStep.ready).to.equal(NO);
        expect(makeDestDirStep.dirUrl).to.beNil;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });
        
        expect(makeDestDirStep.ready).to.equal(YES);
        expect(makeDestDirStep.dirUrl).to.equal([reportsDir URLByAppendingPathComponent:@"ZippedHtmlImportProcessSpec" isDirectory:YES]);
    });

    it(@"cancels the import if the validation fails", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/readme.txt"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });

        expect(validateStep.finished).to.equal(YES);
        expect(validateStep.cancelled).to.equal(NO);
        expect(validateStep.isLayoutValid).to.equal(NO);

        NSArray *remainingSteps = [import.steps subarrayWithRange:NSMakeRange(1, import.steps.count - 1)];
        assertThat(remainingSteps, everyItem(hasProperty(@"isCancelled", isTrue())));
    });

    it(@"is ready to unzip when the dest dir is created", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = import.steps.firstObject;
        MkdirOperation *makeDestDir = import.steps[1];
        UnzipOperation *unzip = import.steps[2];

        expect(unzip.dependencies).to.contain(makeDestDir);
        expect(unzip.ready).to.equal(NO);
        expect(unzip.destDir).to.beNil;

        makeDestDir = OCMPartialMock(makeDestDir);
        OCMStub([makeDestDir main]);
        OCMStub([makeDestDir dirWasCreated]).andReturn(YES);
        OCMStub([makeDestDir dirExisted]).andReturn(NO);

        [validation start];

        waitUntil(^(DoneCallback done) {
            if (validation.finished) {
                done();
            }
        });

        [makeDestDir start];

        waitUntil(^(DoneCallback done) {
            if (makeDestDir.finished) {
                done();
            }
        });

        expect(unzip.ready).to.equal(YES);
        expect(unzip.destDir).to.equal(reportsDir);
    });

    it(@"is ready to unzip when the dest dir already existed", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = import.steps.firstObject;
        MkdirOperation *makeDestDir = import.steps[1];
        UnzipOperation *unzip = import.steps[2];

        expect(unzip.dependencies).to.contain(makeDestDir);
        expect(unzip.ready).to.equal(NO);
        expect(unzip.destDir).to.beNil;

        makeDestDir = OCMPartialMock(makeDestDir);
        OCMStub([makeDestDir main]);
        OCMStub([makeDestDir dirWasCreated]).andReturn(NO);
        OCMStub([makeDestDir dirExisted]).andReturn(YES);

        [validation start];

        waitUntil(^(DoneCallback done) {
            if (validation.finished) {
                done();
            }
        });

        [makeDestDir start];

        waitUntil(^(DoneCallback done) {
            if (makeDestDir.finished) {
                done();
            }
        });

        expect(unzip.ready).to.equal(YES);
        expect(unzip.destDir).to.equal(reportsDir);
    });

    it(@"cancels the import when the dest dir cannot be created and did not exist", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"index.html", @"icon.png"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = import.steps.firstObject;
        MkdirOperation *makeDestDir = OCMPartialMock(import.steps[1]);
        OCMStub([makeDestDir main]);
        OCMStub([makeDestDir dirWasCreated]).andReturn(NO);
        OCMStub([makeDestDir dirExisted]).andReturn(NO);

        [validation start];

        waitUntil(^(DoneCallback done) {
            if (validation.finished) {
                done();
            }
        });

        [makeDestDir start];

        waitUntil(^(DoneCallback done) {
            if (makeDestDir.finished) {
                done();
            }
        });

        NSArray *remainingSteps = [import.steps subarrayWithRange:NSMakeRange(2, import.steps.count - 2)];
        assertThat(remainingSteps, everyItem(hasProperty(@"isCancelled", isTrue())));
    });

    it(@"unzips to the reports dir when zip has base dir", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;
        UnzipOperation *unzipStep = import.steps[2];

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
        MkdirOperation *mkdirStep = import.steps[1];
        UnzipOperation *unzipStep = import.steps[2];

        NSString *baseDirName = @"ZippedHtmlImportProcessSpec";
        NSURL *destDir = [reportsDir URLByAppendingPathComponent:baseDirName isDirectory:YES];

        expect(mkdirStep.dirUrl).to.beNil;
        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });

        expect(mkdirStep.dirUrl).to.equal(destDir);
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
        UnzipOperation *unzipStep = import.steps[2];

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
