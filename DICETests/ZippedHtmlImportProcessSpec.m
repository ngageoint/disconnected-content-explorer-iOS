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

#import <OCMock/OCMock.h>

#import "HtmlReportType.h"
#import "UnzipOperation.h"
#import "FileOperations.h"
#import "ParseJsonOperation.h"
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

    ZipFile *mockZipFile = OCMClassMock([ZipFile class]);
    OCMStub([mockZipFile fileName]).andReturn(report.url.path);
    OCMStub([mockZipFile listFileInZipInfos]).andReturn(entries);

    return mockZipFile;
}

@end



SpecBegin(ZippedHtmlImportProcess)

describe(@"ZippedHtmlImportProcess", ^{

    NSFileManager *fileManager = OCMClassMock([NSFileManager class]);
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

        [(id)zipFile stopMocking];
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

        [(id)zipFile stopMocking];
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

        [(id)zipFile stopMocking];
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

        [(id)makeDestDir stopMocking];
        [(id)zipFile stopMocking];
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

        [(id)makeDestDir stopMocking];
        [(id)zipFile stopMocking];
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

        [(id)makeDestDir stopMocking];
        [(id)zipFile stopMocking];
    });

    it(@"unzips to the reports dir when zip has base dir", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;
        MkdirOperation *makeDestDirStep = OCMPartialMock(import.steps[1]);
        UnzipOperation *unzipStep = import.steps[2];

        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });

        OCMStub([makeDestDirStep main]);
        OCMStub([makeDestDirStep dirWasCreated]).andReturn(NO);
        OCMStub([makeDestDirStep dirExisted]).andReturn(YES);

        [makeDestDirStep start];

        waitUntil(^(DoneCallback done) {
            if (makeDestDirStep.finished) {
                done();
            }
        });

        expect(unzipStep.destDir).to.equal(reportsDir);

        [(id)makeDestDirStep stopMocking];
        [(id)zipFile stopMocking];
    });

    it(@"creates and unzips to dir named after zip file when zip has no base dir", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = import.steps.firstObject;
        MkdirOperation *makeDestDirStep = OCMPartialMock(import.steps[1]);
        UnzipOperation *unzipStep = import.steps[2];

        NSString *baseDirName = @"ZippedHtmlImportProcessSpec";
        NSURL *destDir = [reportsDir URLByAppendingPathComponent:baseDirName isDirectory:YES];

        expect(makeDestDirStep.dirUrl).to.beNil;
        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        waitUntil(^(DoneCallback done) {
            if (validateStep.finished) {
                done();
            }
        });

        expect(makeDestDirStep.dirUrl).to.equal(destDir);

        OCMStub([makeDestDirStep main]);
        OCMStub([makeDestDirStep dirExisted]).andReturn(NO);
        OCMStub([makeDestDirStep dirWasCreated]).andReturn(YES);

        [makeDestDirStep start];

        waitUntil(^(DoneCallback done) {
            if (makeDestDirStep.finished) {
                done();
            }
        });

        expect(unzipStep.destDir).to.equal(destDir);

        [(id)makeDestDirStep stopMocking];
        [(id)zipFile stopMocking];
    });

    it(@"updates the report url on the main thread after unzipping with base dir", ^{
        Report *report = OCMPartialMock(initialReport);
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:report
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = import.steps.firstObject;

        [validation start];

        waitUntil(^(DoneCallback done) {
            if (validation.finished) {
                done();
            }
        });

        NSURL *expectedPath = [reportsDir URLByAppendingPathComponent:@"base" isDirectory:YES];
        __block BOOL wasMainThread = NO;
        __block BOOL urlWasSet = NO;
        UnzipOperation *unzip = import.steps[2];
        UnzipOperation *mockUnzip = OCMPartialMock(unzip);
        OCMStub([mockUnzip wasSuccessful]).andReturn(YES);
        OCMExpect([report setUrl:expectedPath]).andDo(^(NSInvocation *invocation) {
            wasMainThread = [NSThread currentThread] == [NSThread mainThread];
            urlWasSet = YES;
        });

        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [import stepWillFinish:unzip stepIndex:2];
        });

        waitUntil(^(DoneCallback done) {
            if (urlWasSet) {
                done();
            }
        });

        expect(wasMainThread).to.equal(YES);
        OCMVerifyAll((id)report);

        [(id)report stopMocking];
        [(id)mockUnzip stopMocking];
        [(id)zipFile stopMocking];
    });

    it(@"updates the report url on the main thread after unzipping without base dir", ^{
        Report *report = OCMPartialMock(initialReport);
        ZipFile *zipFile = [TestUtil mockZipForReport:report entryNames:@[@"index.html", @"images/", @"images/icon.png"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:report
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = import.steps.firstObject;

        [validation start];

        waitUntil(^(DoneCallback done) {
            if (validation.finished) {
                done();
            }
        });

        NSURL *expectedPath = [reportsDir URLByAppendingPathComponent:@"ZippedHtmlImportProcessSpec" isDirectory:YES];
        __block BOOL wasMainThread = NO;
        __block BOOL urlWasSet = NO;
        UnzipOperation *unzip = import.steps[2];
        UnzipOperation *mockUnzip = OCMPartialMock(unzip);
        OCMStub([mockUnzip wasSuccessful]).andReturn(YES);
        OCMExpect([report setUrl:expectedPath]).andDo(^(NSInvocation *invocation) {
            wasMainThread = [NSThread currentThread] == [NSThread mainThread];
            urlWasSet = YES;
        });

        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [import stepWillFinish:unzip stepIndex:2];
        });

        waitUntil(^(DoneCallback done) {
            if (urlWasSet) {
                done();
            }
        });

        expect(wasMainThread).to.equal(YES);
        OCMVerifyAll((id)report);

        [(id)report stopMocking];
        [(id)mockUnzip stopMocking];
        [(id)zipFile stopMocking];
    });

    it(@"parses the report descriptor if available at root", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"index.html", @"metadata.json"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = import.steps.firstObject;
        UnzipOperation *unzip = import.steps[2];
        ParseJsonOperation *parseMetaData = import.steps[3];

        expect(parseMetaData.dependencies).to.contain(unzip);

        [validation start];

        waitUntil(^(DoneCallback done) {
            if (validation.finished) {
                done();
            }
        });

        expect(parseMetaData.jsonUrl).to.equal([reportsDir URLByAppendingPathComponent:@"ZippedHtmlImportProcessSpec/metadata.json"]);

        [(id)zipFile stopMocking];
    });

    it(@"parses the report descriptor if available in base dir", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"test/", @"test/index.html", @"test/metadata.json"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = import.steps.firstObject;
        UnzipOperation *unzip = import.steps[2];
        ParseJsonOperation *parseMetaData = import.steps[3];

        expect(parseMetaData.dependencies).to.contain(unzip);

        [validation start];

        waitUntil(^(DoneCallback done) {
            if (validation.finished) {
                done();
            }
        });

        expect(parseMetaData.jsonUrl).to.equal([reportsDir URLByAppendingPathComponent:@"test/metadata.json"]);

        [(id)zipFile stopMocking];
    });

    it(@"cancels parsing report descriptor if not available", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"test/", @"test/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = import.steps.firstObject;
        UnzipOperation *unzip = import.steps[2];
        ParseJsonOperation *parseMetaData = import.steps[3];

        expect(parseMetaData.dependencies).to.contain(unzip);

        [validation start];

        waitUntil(^(DoneCallback done) {
            if (validation.finished) {
                done();
            }
        });

        expect(parseMetaData.cancelled).to.equal(YES);

        [(id)zipFile stopMocking];
    });

    it(@"updates the report on the main thread after parsing the descriptor", ^{
        Report *report = OCMPartialMock(initialReport);
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"test/", @"test/index.html", @"test/metadata.json"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:report
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        __block BOOL wasMainThread = NO;
        __block BOOL reportUpdated = NO;
        NSDictionary *descriptor = @{ @"title": @"On Main Thread" };
        ParseJsonOperation *parseDescriptor = import.steps[3];
        id mockParseDescriptor = OCMPartialMock(parseDescriptor);
        OCMStub([mockParseDescriptor parsedJsonDictionary]).andReturn(descriptor);
        [OCMExpect([report setPropertiesFromJsonDescriptor:[OCMArg any]]) andDo:^(NSInvocation *invocation) {
            wasMainThread = [NSThread mainThread] == [NSThread currentThread];
            reportUpdated = YES;
        }];

        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [import stepWillFinish:parseDescriptor stepIndex:3];
        });

        waitUntil(^(DoneCallback done) {
            if (reportUpdated) {
                done();
            }
        });

        expect(wasMainThread).to.equal(YES);
        OCMVerifyAll((id)report);

        [(id)report stopMocking];
        [(id)mockParseDescriptor stopMocking];
        [(id)zipFile stopMocking];
    });

    it(@"deletes the zip file after unzipping successfully", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        UnzipOperation *unzipStep = import.steps[2];
        DeleteFileOperation *deleteStep = import.steps.lastObject;

        expect(deleteStep.dependencies).to.contain(unzipStep);
        expect(deleteStep.fileUrl).to.equal(initialReport.url);

        [(id)zipFile stopMocking];
    });

    it(@"leaves the zip file if an error occurs", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
             destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        UnzipOperation *unzipStep = import.steps[2];
        DeleteFileOperation *deleteStep = import.steps.lastObject;

        UnzipOperation *mockUnzipStep = OCMPartialMock(unzipStep);
        OCMStub([mockUnzipStep main]);
        OCMStub([mockUnzipStep wasSuccessful]).andReturn(NO);

        [import stepWillFinish:unzipStep stepIndex:2];

        expect(deleteStep.cancelled).to.equal(YES);

        [(id)mockUnzipStep stopMocking];
    });
    
    it(@"reports unzip progress updates", ^{
        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
             destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        id<ImportDelegate> importListener = OCMProtocolMock(@protocol(ImportDelegate));
        import.delegate = importListener;
        OCMExpect([importListener reportWasUpdatedByImportProcess:import]);
        OCMExpect([importListener reportWasUpdatedByImportProcess:import]);
        OCMExpect([importListener reportWasUpdatedByImportProcess:import]);

        UnzipOperation *unzipStep = import.steps[2];

        [import unzipOperation:unzipStep didUpdatePercentComplete:13];
        expect(initialReport.summary).to.contain(@"13%");

        [import unzipOperation:unzipStep didUpdatePercentComplete:29];
        expect(initialReport.summary).to.contain(@"29%");

        [import unzipOperation:unzipStep didUpdatePercentComplete:100];
        expect(initialReport.summary).to.contain(@"100%");

        OCMVerifyAll((id)importListener);
    });

    xit(@"unzips the file to a temporary directory", ^{
//        NSString *uuid = [[NSUUID UUID] UUIDString];
//        NSString *tempDirName = [@"temp-" stringByAppendingString:uuid];
//        NSURL *tempDir = [reportsDir URLByAppendingPathComponent:tempDirName];
//
//        [given([fileManager createTempDir]) willReturn:tempDir];
//
//        ZipFile *zipFile = [TestUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
//        id<ImportProcess> import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
//            destDir:reportsDir zipFile:zipFile fileManager:fileManager];
//        UnzipOperation *unzipStep = import.steps[2];
//
//        expect(unzipStep.zipFile).to.equal(initialReport.url);
//        expect(unzipStep.destDir).to.equal(tempDir);

        failure(@"unimplemented - unnecessary?  could make concurrency issues simpler");
    });

    xit(@"moves the extracted content to the reports directory", ^{
        failure(@"unimplemented - only if unzipping to temp dirs");
    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
