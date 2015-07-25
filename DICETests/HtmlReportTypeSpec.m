//
//  ReportTypeTests.m
//  DICE
//
//  Created by Robert St. John on 5/22/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//


#import <Specta/Specta.h>
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#import "HtmlReportType.h"
#import "ResourceTypes.h"
#import "SimpleFileManager.h"
#import "DeleteFileOperation.h"
#import "UnzipOperation.h"


@interface TestQueue : NSOperationQueue

@property (strong, nonatomic, readonly) NSOperation *lastOperation;

@end


@implementation TestQueue

- (void)addOperation:(NSOperation *)op
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        _lastOperation = op;
    });
}

@end


@interface TestFileInfo : NSObject <FileInfo>

@property (strong, readonly, nonatomic) NSURL *path;
@property (readonly, nonatomic) BOOL isDirectory;
@property (readonly, nonatomic) BOOL isRegularFile;

@end


@implementation TestFileInfo

- (instancetype)initDirectoryWithPath:(NSURL *)path
{
    self = [super init];

    _path = path;
    _isDirectory = YES;
    _isRegularFile = NO;

    return self;
}

- (instancetype)initRegularFileWithPath:(NSURL *)path
{
    self = [super init];

    _path = path;
    _isRegularFile = YES;
    _isDirectory = NO;

    return self;
}

- (instancetype)initUnkownWithPath:(NSURL *)path
{
    self = [super init];

    _path = path;
    _isDirectory = NO;
    _isRegularFile = NO;

    return self;
}

@end


SpecBegin(HtmlReportType)

describe(@"HtmlReportType", ^{

    id<SimpleFileManager> const fileManager = mockProtocol(@protocol(SimpleFileManager));
    TestQueue * const workQueue = [[TestQueue alloc] init];

    NSURL * const reportsDir = [NSURL fileURLWithPath:@"/test/reports/"];

    HtmlReportType * const htmlReportType = [[HtmlReportType alloc] initWithFileManager:fileManager];

    beforeAll(^{

    });

    beforeEach(^{

    });

    afterEach(^{
        [((MKTBaseMockObject *)fileManager) reset];
    });


    it(@"could handle a directory if it contains index.html", ^{
        NSURL *dirPath = [reportsDir URLByAppendingPathComponent:@"test_report"];
        NSURL *indexPath = [dirPath URLByAppendingPathComponent:@"index.html"];

        [given([fileManager infoForPath:dirPath]) willReturn:[[TestFileInfo alloc] initDirectoryWithPath:dirPath]];
        [given([fileManager infoForPath:indexPath]) willReturn:[[TestFileInfo alloc] initRegularFileWithPath:indexPath]];

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(YES);
    });

    it(@"could not handle a directory without index.html", ^{
        NSURL *dirPath = [reportsDir URLByAppendingPathComponent:@"test_reports"];
        NSURL *indexPath = [reportsDir URLByAppendingPathComponent:@"index.html"];

        [given([fileManager infoForPath:dirPath]) willReturn:[[TestFileInfo alloc] initDirectoryWithPath:dirPath]];
        [given([fileManager infoForPath:indexPath]) willReturn:nil];

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(NO);
    });

    it(@"could not handle a directory when index.html is a directory", ^{
        NSURL *dirPath = [reportsDir URLByAppendingPathComponent:@"test_reports"];
        NSURL *indexPath = [reportsDir URLByAppendingPathComponent:@"index.html"];

        [given([fileManager infoForPath:dirPath]) willReturn:[[TestFileInfo alloc] initDirectoryWithPath:dirPath]];
        [given([fileManager infoForPath:indexPath]) willReturn:[[TestFileInfo alloc] initDirectoryWithPath:dirPath]];

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(NO);
    });

    it(@"could handle a zip file", ^{
        NSURL *zipPath = [reportsDir URLByAppendingPathComponent:@"test_report.zip"];

        [given([fileManager infoForPath:zipPath]) willReturn:[[TestFileInfo alloc] initRegularFileWithPath:zipPath]];

        expect([htmlReportType couldHandleFile:zipPath]).to.equal(YES);
    });

    it(@"could handle an html file", ^{
        NSURL *htmlPath = [reportsDir URLByAppendingPathComponent:@"test_report.html"];

        [given([fileManager infoForPath:htmlPath]) willReturn:[[TestFileInfo alloc] initRegularFileWithPath:htmlPath]];

        expect([htmlReportType couldHandleFile:htmlPath]).to.equal(YES);
    });

    it(@"could not handle something else", ^{
        NSURL *filePath = [reportsDir URLByAppendingPathComponent:@"test_report.txt"];

        [given([fileManager infoForPath:filePath]) willReturn:[[TestFileInfo alloc] initRegularFileWithPath:filePath]];

        expect([htmlReportType couldHandleFile:filePath]).to.equal(NO);
    });

    it(@"could not handle a non-regular file or non-directory", ^{
        NSURL *filePath = [reportsDir URLByAppendingPathComponent:@"i_dunno"];

        [given([fileManager infoForPath:filePath]) willReturn:[[TestFileInfo alloc] init]];

        expect([htmlReportType couldHandleFile:filePath]).to.equal(NO);
    });

    describe(@"importing from zip file", ^{

        it(@"validates the zip file contents first", ^{
            Report *report = [[Report alloc] init];
            report.url = [reportsDir URLByAppendingPathComponent:@"validate_test.zip"];
            id<ImportProcess> import = [htmlReportType createImportProcessForReport:report];

            NSOperation *validate = [import nextStep];

            expect(validate).to.beInstanceOf([ValidateHtmlLayoutOperation class]);
        });

        it(@"unzips the file to a temporary directory", ^{
            NSString *uuid = [[NSUUID UUID] UUIDString];
            NSString *reportName = [NSString stringWithFormat:@"%@.zip", uuid];
            NSString *tempDirName = [@"temp-" stringByAppendingString:uuid];
            NSURL *tempDir = [reportsDir URLByAppendingPathComponent:tempDirName];

            Report *report = [[Report alloc] init];
            report.url = [reportsDir URLByAppendingPathComponent:reportName];

            [given([fileManager createTempDir]) willReturn:tempDir];

            id<ImportProcess> import = [htmlReportType createImportProcessForReport:report];
            UnzipOperation *unzipStep = (UnzipOperation *) [import nextStep];

            expect(unzipStep.zipFile).to.equal(report.url);
            expect(unzipStep.destDir).to.equal(tempDir);
        });

        it(@"deletes the zip file after unzipping successfully", ^{
            Report *report = [[Report alloc] init];
            report.url = [reportsDir URLByAppendingPathComponent:@"success.zip"];

            id<ImportProcess> import = [htmlReportType createImportProcessForReport:report];

            NSOperation *lastStep = nil;
            while ([import hasNextStep]) {
                lastStep = [import nextStep];
            }

            expect(lastStep).to.beInstanceOf([DeleteFileOperation class]);
        });

        it(@"moves the content to the reports directory", ^{
            failure(@"unimplemented");
        });

        it(@"leaves the zip file if an error occurs", ^{
            failure(@"unimplemented");
        });

        it(@"reports unzip progress updates", ^{
            failure(@"unimplemented");
        });
    });

    describe(@"importing from directory", ^{

    });

});

describe(@"ValidateHtmlLayoutOperation", ^{

    it(@"validates a zip with index.html at the root level", ^{
        failure(@"unimplemented");
    });

    it(@"validates a zip with index.html in a top-level directory", ^{
        failure(@"unimplemented");
    });

    it(@"invalidates a zip without index.html", ^{
        failure(@"unimplemented");
    });

    it(@"invalidates a zip with index.html in a lower level directory", ^{
        failure(@"unimplemented");
    });

    it(@"invalidates a zip with unrecognized entries at the root level", ^{
        failure(@"unimplemented");
    });

});

SpecEnd
