//
//  ZippedHtmlImportProcessSpec.m
//  DICE
//
//  Created by Robert St. John on 7/31/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "UnzipOperation.h"
#import "ValidateHtmlLayoutOperation.h"
#import "ZippedHtmlImportProcess.h"
#import "FileOperations.h"
#import "ParseJsonOperation.h"
#import "OZFileInZipInfo+Internals.h"
#import "ImportProcess+Internal.h"
#import "ZipFile+FileTree.h"
#import "OZZipFile+Standard.h"


@interface ZippedHtmlImportProcessSpec_MkdirOperation : MkdirOperation

@property BOOL testDirWasCreated;
@property BOOL testDirExisted;

@end


@implementation ZippedHtmlImportProcessSpec_MkdirOperation

- (void)main
{
    NSLog(@"ZippedHtmlImportProcessSpec_MkdirOperation: %@", self.dirUrl);
}

- (BOOL)dirWasCreated
{
    return self.testDirWasCreated;
}

- (BOOL)dirExisted
{
    return self.testDirExisted;
}

@end


@interface ZippedHtmlImportProcessSpec_UnzipOperation : UnzipOperation

@property BOOL testWasSuccessful;

@end


@implementation ZippedHtmlImportProcessSpec_UnzipOperation

- (void)main
{
    NSLog(@"ZippedHtmlImportProcessSpec_UnzipOperation: %@", self.destDir);
}

- (BOOL)wasSuccessful
{
    return self.testWasSuccessful;
}

@end


@interface ZippedHtmlImportProcessSpec_ParseJsonOperation : ParseJsonOperation

@property NSDictionary *testParsedJsonDictionary;

@end

@implementation ZippedHtmlImportProcessSpec_ParseJsonOperation

- (NSDictionary *)parsedJsonDictionary
{
    return self.testParsedJsonDictionary;
}

- (void)main
{
    NSLog(@"ZippedHtmlImportProcessSpec_ParseJsonOperation: %@", self.jsonUrl);
}

@end


@interface ZippedHtmlImportProcessSpecUtil : NSObject

+ (OZZipFile *)mockZipForReport:(Report *)report entryNames:(NSArray *)entryNames;

@end

@implementation ZippedHtmlImportProcessSpecUtil

+ (OZZipFile *)mockZipForReport:(Report *)report entryNames:(NSArray *)entryNames
{
    NSMutableArray *entries = [NSMutableArray array];

    for (NSString *entryName in entryNames) {
        [entries addObject:[[OZFileInZipInfo alloc] initWithName:entryName length:0 level:OZZipCompressionLevelDefault crypted:NO size:0 date:nil crc32:0]];
    }

    OZZipFile *mockZip = mock([OZZipFile class]);
    [given([mockZip fileName]) willReturn:report.url.path];
    [given([mockZip listFileInZipInfos]) willReturn:entries];
    [given([mockZip fileTree_enumerateFiles]) willReturn:nil];

    return mockZip;
}

@end


SpecBegin(ZippedHtmlImportProcess)

describe(@"ZippedHtmlImportProcess", ^{

    NSURL * const reportsDir = [NSURL URLWithString:@"file:///apps/dice/Documents"];
    NSString * const reportFileName = @"ZippedHtmlImportProcessSpec.zip";

    __block Report *initialReport;
    __block NSFileManager *fileManager;

    beforeAll(^{

    });

    beforeEach(^{
        initialReport = [[Report alloc] init];
        initialReport.url = [reportsDir URLByAppendingPathComponent:reportFileName];
        initialReport.title = reportFileName;

        fileManager = mock([NSFileManager class]);
    });

    afterEach(^{
        stopMocking(fileManager);
        fileManager = nil;
    });

    afterAll(^{

    });

    it(@"validates the zip file contents first", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[
            @"base/",
            @"base/index.html"
        ]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        expect(import.steps.firstObject).to.beInstanceOf([ValidateHtmlLayoutOperation class]);

        stopMocking(zipFile);
    });

    it(@"makes the base dir when the validation finishes successfully", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"icon.gif", @"index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = (ValidateHtmlLayoutOperation *) import.steps.firstObject;
        MkdirOperation *makeDestDirStep = (MkdirOperation *) import.steps[1];

        expect(makeDestDirStep.dependencies).to.contain(validateStep);
        expect(makeDestDirStep.ready).to.equal(NO);
        expect(makeDestDirStep.dirUrl).to.beNil;

        [validateStep start];

        assertWithTimeout(1.0, thatEventually(@(validateStep.isFinished && makeDestDirStep.isReady)), isTrue());

        expect(validateStep.finished).to.equal(YES);
        expect(makeDestDirStep.ready).to.equal(YES);
        expect(makeDestDirStep.dirUrl).to.equal([reportsDir URLByAppendingPathComponent:@"ZippedHtmlImportProcessSpec" isDirectory:YES]);

        stopMocking(zipFile);
    });

    it(@"cancels the import if the validation fails", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/readme.txt"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = (ValidateHtmlLayoutOperation *) import.steps.firstObject;

        [validateStep start];

        assertWithTimeout(1.0, thatEventually(@(validateStep.isFinished)), isTrue());

        expect(validateStep.finished).to.equal(YES);
        expect(validateStep.cancelled).to.equal(NO);
        expect(validateStep.isLayoutValid).to.equal(NO);

        NSArray *remainingSteps = [import.steps subarrayWithRange:NSMakeRange(1, import.steps.count - 1)];
        assertThat(remainingSteps, everyItem(hasProperty(@"isCancelled", isTrue())));

        stopMocking(zipFile);
    });

    it(@"is ready to unzip when the dest dir is created", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        MkdirOperation *makeDestDir = (MkdirOperation *) import.steps[1];
        UnzipOperation *unzip = (UnzipOperation *) import.steps[2];

        expect(unzip.dependencies).to.contain(makeDestDir);

        stopMocking(zipFile);
    });

    it(@"cancels the import when the dest dir cannot be created and did not exist", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"index.html", @"icon.png"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = (ValidateHtmlLayoutOperation *) import.steps.firstObject;
        MkdirOperation *makeDestDir = (MkdirOperation *) import.steps[1];

        [validation start];

        assertWithTimeout(1.0, thatEventually(@(validation.isFinished && makeDestDir.isReady)), isTrue());

        [makeDestDir start];

        assertWithTimeout(1.0, thatEventually(@(makeDestDir.isFinished)), isTrue());

        expect(makeDestDir.dirExisted).to.equal(NO);
        expect(makeDestDir.dirWasCreated).to.equal(NO);

        NSArray *remainingSteps = [import.steps subarrayWithRange:NSMakeRange(2, import.steps.count - 2)];
        assertThat(remainingSteps, everyItem(hasProperty(@"isCancelled", isTrue())));

        stopMocking(zipFile);
    });

    it(@"unzips to the reports dir when zip has base dir", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = (ValidateHtmlLayoutOperation *) import.steps.firstObject;
        MkdirOperation *makeDestDirStep = (MkdirOperation *) import.steps[1];
        UnzipOperation *unzipStep = (UnzipOperation *) import.steps[2];

        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        assertWithTimeout(1.0, thatEventually(@(validateStep.isFinished && makeDestDirStep.isReady)), isTrue());

        [given([fileManager createDirectoryAtURL:anything() withIntermediateDirectories:YES attributes:anything() error:NULL]) willReturnBool:YES];
        [makeDestDirStep start];

        assertWithTimeout(1.0, thatEventually(@(makeDestDirStep.isFinished && unzipStep.isReady)), isTrue());

        expect(unzipStep.destDir).to.equal(reportsDir);

        stopMocking(zipFile);
    });

    it(@"creates and unzips to dir named after zip file when zip has no base dir", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validateStep = (ValidateHtmlLayoutOperation *) import.steps.firstObject;
        MkdirOperation *makeDestDirStep = (MkdirOperation *) import.steps[1];
        UnzipOperation *unzipStep = (UnzipOperation *) import.steps[2];

        NSString *baseDirName = @"ZippedHtmlImportProcessSpec";
        NSURL *destDir = [reportsDir URLByAppendingPathComponent:baseDirName isDirectory:YES];

        expect(makeDestDirStep.dirUrl).to.beNil;
        expect(unzipStep.destDir).to.beNil;

        [validateStep start];

        assertWithTimeout(1.0, thatEventually(@(validateStep.isFinished && makeDestDirStep.isReady)), isTrue());

        expect(makeDestDirStep.dirUrl).to.equal(destDir);

        [given([fileManager createDirectoryAtURL:anything() withIntermediateDirectories:YES attributes:anything() error:NULL]) willReturnBool:YES];

        [makeDestDirStep start];

        assertWithTimeout(1.0, thatEventually(@(makeDestDirStep.isFinished && unzipStep.isReady)), isTrue());

        expect(unzipStep.destDir).to.equal(destDir);

        stopMocking(zipFile);
    });

    it(@"updates the report url on the main thread after unzipping with base dir", ^{
        Report *report = mock([Report class]);
        [given([report title]) willReturn:initialReport.title];
        [given([report url]) willReturn:initialReport.url];
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:report
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];
        NSOperationQueue *ops = [[NSOperationQueue alloc] init];

        ZippedHtmlImportProcessSpec_MkdirOperation *testMkdir = [[ZippedHtmlImportProcessSpec_MkdirOperation alloc] initWithFileMananger:fileManager];
        testMkdir.testDirWasCreated = YES;
        ZippedHtmlImportProcessSpec_UnzipOperation *testUnzip = [[ZippedHtmlImportProcessSpec_UnzipOperation alloc]
            initWithZipFile:zipFile destDir:reportsDir fileManager:fileManager];
        ValidateHtmlLayoutOperation *validate = (ValidateHtmlLayoutOperation *) import.steps[ZippedHtmlImportValidateStep];
        MkdirOperation *mkdir = (MkdirOperation *) import.steps[ZippedHtmlImportMakeBaseDirStep];
        UnzipOperation *unzip = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        ParseJsonOperation *parse = (ParseJsonOperation *) import.steps[ZippedHtmlImportParseDescriptorStep];
        [mkdir removeDependency:validate];
        [unzip removeDependency:mkdir];
        [parse removeDependency:unzip];
        NSMutableArray<NSOperation *> *stepsMod = [import.steps mutableCopy];
        stepsMod[ZippedHtmlImportMakeBaseDirStep] = testMkdir;
        stepsMod[ZippedHtmlImportUnzipStep] = testUnzip;
        import.steps = stepsMod;

        [ops addOperations:@[validate, testMkdir] waitUntilFinished:YES];

        __block BOOL urlWasSetOnMainThread = NO;
        NSURL *expectedPath = [reportsDir URLByAppendingPathComponent:@"base" isDirectory:YES];
        [givenVoid([report setUrl:anything()]) willDo:^id(NSInvocation *invocation) {
            urlWasSetOnMainThread = [NSThread currentThread] == [NSThread mainThread];
            return nil;
        }];

        testUnzip.testWasSuccessful = YES;
        [ops addOperations:@[testUnzip] waitUntilFinished:YES];

        assertWithTimeout(1.0, thatEventually(@(urlWasSetOnMainThread)), isTrue());

        [verify(report) setUrl:equalTo(expectedPath)];

        stopMocking(report);
        stopMocking(zipFile);
    });

    it(@"updates the report url on the main thread after unzipping without base dir", ^{
        Report *report = mock([Report class]);
        [given([report title]) willReturn:initialReport.title];
        [given([report url]) willReturn:initialReport.url];
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:report entryNames:@[@"index.html", @"images/", @"images/icon.png"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:report
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];
        NSOperationQueue *ops = [[NSOperationQueue alloc] init];

        ZippedHtmlImportProcessSpec_MkdirOperation *testMkdir = [[ZippedHtmlImportProcessSpec_MkdirOperation alloc] initWithFileMananger:fileManager];
        testMkdir.testDirWasCreated = YES;
        ZippedHtmlImportProcessSpec_UnzipOperation *testUnzip = [[ZippedHtmlImportProcessSpec_UnzipOperation alloc]
            initWithZipFile:zipFile destDir:reportsDir fileManager:fileManager];
        testUnzip.testWasSuccessful = YES;
        ValidateHtmlLayoutOperation *validate = (ValidateHtmlLayoutOperation *) import.steps[ZippedHtmlImportValidateStep];
        MkdirOperation *mkdir = (MkdirOperation *) import.steps[ZippedHtmlImportMakeBaseDirStep];
        UnzipOperation *unzip = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        ParseJsonOperation *parse = (ParseJsonOperation *) import.steps[ZippedHtmlImportParseDescriptorStep];
        [mkdir removeDependency:validate];
        [unzip removeDependency:mkdir];
        [parse removeDependency:unzip];
        NSMutableArray<NSOperation *> *stepsMod = [import.steps mutableCopy];
        stepsMod[ZippedHtmlImportMakeBaseDirStep] = testMkdir;
        stepsMod[ZippedHtmlImportUnzipStep] = testUnzip;
        import.steps = stepsMod;

        [ops addOperations:@[validate, testMkdir] waitUntilFinished:YES];

        __block BOOL urlWasSetOnMainThread = NO;
        NSURL *expectedPath = [reportsDir URLByAppendingPathComponent:@"ZippedHtmlImportProcessSpec" isDirectory:YES];
        [givenVoid([report setUrl:anything()]) willDo:^id(NSInvocation *invocation) {
            urlWasSetOnMainThread = [NSThread currentThread] == [NSThread mainThread];
            return nil;
        }];

        [ops addOperations:@[testUnzip] waitUntilFinished:YES];

        assertWithTimeout(1.0, thatEventually(@(urlWasSetOnMainThread)), isTrue());

        [verify(report) setUrl:equalTo(expectedPath)];

        stopMocking(report);
        stopMocking(zipFile);
    });

    it(@"parses the report descriptor if available at root", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"index.html", @"metadata.json"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = (ValidateHtmlLayoutOperation *) import.steps[ZippedHtmlImportValidateStep];
        UnzipOperation *unzip = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        ParseJsonOperation *parseMetaData = (ParseJsonOperation *) import.steps[ZippedHtmlImportParseDescriptorStep];

        expect(parseMetaData.dependencies).to.contain(unzip);

        [validation start];

        NSURL *expectedDescriptorUrl = [reportsDir URLByAppendingPathComponent:@"ZippedHtmlImportProcessSpec/metadata.json"];
        assertWithTimeout(1.0, thatEventually(parseMetaData.jsonUrl), equalTo(expectedDescriptorUrl));

        stopMocking(zipFile);
    });

    it(@"parses the report descriptor if available in base dir", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"test/", @"test/index.html", @"test/metadata.json"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = (ValidateHtmlLayoutOperation *) import.steps[ZippedHtmlImportValidateStep];
        UnzipOperation *unzip = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        ParseJsonOperation *parseMetaData = (ParseJsonOperation *) import.steps[ZippedHtmlImportParseDescriptorStep];

        expect(parseMetaData.dependencies).to.contain(unzip);

        [validation start];

        NSURL *expectedDescriptorUrl = [reportsDir URLByAppendingPathComponent:@"test/metadata.json"];
        assertWithTimeout(1.0, thatEventually(parseMetaData.jsonUrl), equalTo(expectedDescriptorUrl));

        stopMocking(zipFile);
    });

    it(@"cancels parsing report descriptor if not available", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"test/", @"test/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        ValidateHtmlLayoutOperation *validation = (ValidateHtmlLayoutOperation *) import.steps[ZippedHtmlImportValidateStep];
        UnzipOperation *unzip = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        ParseJsonOperation *parseMetaData = (ParseJsonOperation *) import.steps[ZippedHtmlImportParseDescriptorStep];

        expect(parseMetaData.dependencies).to.contain(unzip);

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperation:validation];

        assertWithTimeout(1.0, thatEventually(@(parseMetaData.isCancelled && ops.operationCount == 0)), isTrue());

        stopMocking(zipFile);
    });

    it(@"updates the report on the main thread after parsing the descriptor", ^{
        Report *report = mock([Report class]);
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil
            mockZipForReport:initialReport entryNames:@[@"test/", @"test/index.html", @"test/metadata.json"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:report
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        NSMutableArray<NSOperation *> *modSteps = [import.steps mutableCopy];
        import.steps = modSteps;
        ZippedHtmlImportProcessSpec_ParseJsonOperation *modParseDescriptor = [[ZippedHtmlImportProcessSpec_ParseJsonOperation alloc] init];
        NSDictionary *descriptor = @{ @"title": @"On Main Thread" };
        modParseDescriptor.testParsedJsonDictionary = descriptor;
        ParseJsonOperation *parseDescriptor = (ParseJsonOperation *) import.steps[ZippedHtmlImportParseDescriptorStep];
        UnzipOperation *unzip = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        [parseDescriptor removeDependency:unzip];
        modSteps[ZippedHtmlImportParseDescriptorStep] = modParseDescriptor;

        __block BOOL updatedOnMainThread = NO;
        [given([report setPropertiesFromJsonDescriptor:descriptor]) willDo:(id)^(NSInvocation *invocation) {
            updatedOnMainThread = ([NSThread mainThread] == [NSThread currentThread]);
            return nil;
        }];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [import stepWillFinish:modParseDescriptor];
        });

        assertWithTimeout(1.0, thatEventually(@(updatedOnMainThread)), isTrue());

        stopMocking(report);
        stopMocking(zipFile);
    });

    it(@"deletes the zip file after unzipping successfully", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        UnzipOperation *unzipStep = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        DeleteFileOperation *deleteStep = (DeleteFileOperation *) import.steps[ZippedHtmlImportDeleteStep];

        expect(deleteStep.dependencies).to.contain(unzipStep);
        expect(deleteStep.fileUrl).to.equal(initialReport.url);

        stopMocking(zipFile);
    });

    it(@"leaves the zip file if an error occurs", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc]
            initWithReport:initialReport destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        MkdirOperation *mkdirStep = (MkdirOperation *) import.steps[ZippedHtmlImportMakeBaseDirStep];
        UnzipOperation *unzipStep = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        DeleteFileOperation *deleteStep = (DeleteFileOperation *) import.steps[ZippedHtmlImportDeleteStep];
        [unzipStep removeDependency:mkdirStep];

        NSMutableArray<NSOperation *> *modSteps = [import.steps mutableCopy];
        import.steps = modSteps;
        ZippedHtmlImportProcessSpec_UnzipOperation *modUnzipStep = [[ZippedHtmlImportProcessSpec_UnzipOperation alloc]
            initWithZipFile:zipFile destDir:reportsDir fileManager:fileManager];

        modUnzipStep.testWasSuccessful = NO;
        modSteps[ZippedHtmlImportUnzipStep] = modUnzipStep;

        [import stepWillFinish:modUnzipStep];

        expect(deleteStep.isCancelled).to.equal(YES);

        stopMocking(zipFile);
    });

    it(@"reports unzip progress updates", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
             destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        id<ImportDelegate> importListener = mockProtocol(@protocol(ImportDelegate));
        import.delegate = importListener;

        UnzipOperation *unzipStep = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];

        [import unzipOperation:unzipStep didUpdatePercentComplete:13];
        expect(initialReport.summary).to.contain(@"13%");

        [import unzipOperation:unzipStep didUpdatePercentComplete:29];
        expect(initialReport.summary).to.contain(@"29%");

        [import unzipOperation:unzipStep didUpdatePercentComplete:100];
        expect(initialReport.summary).to.contain(@"100%");

        [verifyCount(importListener, times(3)) reportWasUpdatedByImportProcess:import];
    });

    it(@"notifies the delegate on main thread when finished", ^{
        OZZipFile *zipFile = [ZippedHtmlImportProcessSpecUtil mockZipForReport:initialReport entryNames:@[@"base/", @"base/index.html"]];
        ZippedHtmlImportProcess *import = [[ZippedHtmlImportProcess alloc] initWithReport:initialReport
            destDir:reportsDir zipFile:zipFile fileManager:fileManager];

        __block BOOL delegateNotified = NO;
        id<ImportDelegate> importListener = mockProtocol(@protocol(ImportDelegate));
        [givenVoid([importListener importDidFinishForImportProcess:import]) willDo:^id(NSInvocation *invocation) {
            delegateNotified = [NSThread currentThread] == [NSThread mainThread];
            return nil;
        }];
        import.delegate = importListener;

        ValidateHtmlLayoutOperation *validate = (ValidateHtmlLayoutOperation *) import.steps[ZippedHtmlImportValidateStep];
        MkdirOperation *mkdir = (MkdirOperation *) import.steps[ZippedHtmlImportMakeBaseDirStep];
        UnzipOperation *unzip = (UnzipOperation *) import.steps[ZippedHtmlImportUnzipStep];
        ParseJsonOperation *parseDescriptor = (ParseJsonOperation *) import.steps[ZippedHtmlImportParseDescriptorStep];
        DeleteFileOperation *deleteZip = (DeleteFileOperation *) import.steps[ZippedHtmlImportDeleteStep];

        [mkdir removeDependency:validate];
        [unzip removeDependency:mkdir];
        [parseDescriptor removeDependency:unzip];
        [deleteZip removeDependency:unzip];

        ZippedHtmlImportProcessSpec_MkdirOperation *testMkdir = [[ZippedHtmlImportProcessSpec_MkdirOperation alloc] initWithFileMananger:fileManager];
        ZippedHtmlImportProcessSpec_UnzipOperation *testUnzip = [[ZippedHtmlImportProcessSpec_UnzipOperation alloc] initWithZipFile:zipFile destDir:reportsDir fileManager:fileManager];

        [testMkdir addDependency:validate];
        [testUnzip addDependency:testMkdir];
        [parseDescriptor addDependency:testUnzip];
        [deleteZip addDependency:testUnzip];

        testMkdir.testDirExisted = YES;
        testUnzip.testWasSuccessful = YES;

        NSMutableArray<NSOperation *> *testSteps = [import.steps mutableCopy];
        testSteps[ZippedHtmlImportMakeBaseDirStep] = testMkdir;
        testSteps[ZippedHtmlImportUnzipStep] = testUnzip;
        import.steps = testSteps;

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperations:import.steps waitUntilFinished:NO];

        assertWithTimeout(1.0, thatEventually(ops.operations), isEmpty());

        expect(deleteZip.isFinished).to.equal(YES);
        expect(parseDescriptor.isCancelled).to.equal(YES);

        assertWithTimeout(1.0, thatEventually(@(delegateNotified)), isTrue());

        stopMocking(zipFile);
        stopMocking(importListener);
    });



});

SpecEnd
