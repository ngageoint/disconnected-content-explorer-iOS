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

    HtmlReportType * const htmlReportType = [[HtmlReportType alloc] initWithFileManager:fileManager workQueue:workQueue];

    
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

    describe(@"importReport from zip file", ^{

        it(@"unzips the file asynchronously", ^{
            NSString *uuid = [[NSUUID UUID] UUIDString];
            NSString *reportName = [NSString stringWithFormat:@"%@.zip", uuid];
            Report *report = [[Report alloc] init];
            report.url = [reportsDir URLByAppendingPathComponent:reportName];
            [htmlReportType importReport:report];

            expect(workQueue.lastOperation).to.beNil;

            waitUntil(^(DoneCallback done) {
                if (workQueue.lastOperation) {
                    done();
                }
            });

            expect(workQueue.lastOperation).to.beInstanceOf([UnzipOperation class]);

            UnzipOperation *unzip = (UnzipOperation *)workQueue.lastOperation;
            expect(unzip.zipFile).to.equal(report.url);
        });

        it(@"unzips the file to a temporary directory", ^{
            NSString *uuid = [[NSUUID UUID] UUIDString];
            NSString *reportName = [NSString stringWithFormat:@"%@.zip", uuid];
            NSString *tempDirName = [@"temp-" stringByAppendingString:uuid];
            NSURL *tempDir = [reportsDir URLByAppendingPathComponent:tempDirName];

            Report *report = [[Report alloc] init];
            report.url = [reportsDir URLByAppendingPathComponent:reportName];

            [given([fileManager createTempDir]) willReturn:tempDir];

            [htmlReportType importReport:report];

            waitUntil(^(DoneCallback done) {
                if (workQueue.lastOperation) {
                    done();
                }
            });

            UnzipOperation *unzip = (UnzipOperation *)workQueue.lastOperation;

            expect(unzip.zipFile).to.equal(report.url);
            expect(unzip.destDir).to.equal(tempDir);
        });

        it(@"deletes the zip file after unzipping successfully", ^{
            Report *report = [[Report alloc] init];
            report.url = [reportsDir URLByAppendingPathComponent:@"success.zip"];

            [given([fileManager deleteFileAtPath:report.url]) willReturnBool:YES];

            [htmlReportType importReport:report];

            waitUntil(^(DoneCallback done) {
                if (workQueue.lastOperation) {
                    done();
                }
            });

            [verify(fileManager) deleteFileAtPath:report.url];
        });

        it(@"leaves the zip file if an error occurs", ^{
            failure(@"unimplemented");
        });

        it(@"reports unzip progress updates", ^{
            failure(@"unimplemented");
        });
    });

});

SpecEnd