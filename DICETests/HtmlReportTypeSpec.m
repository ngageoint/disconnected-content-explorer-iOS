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
#import "MoveFileOperation.h"
#import "DeleteFileOperation.h"
#import "UnzipOperation.h"
#import "FileInZipInfo.h"


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

});

describe(@"ValidateHtmlLayoutOperation", ^{

    it(@"validates a zip with index.html at the root level", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;

        [op start];

        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(YES);
        expect(op.indexDirPath).to.equal(@"");
    });

    it(@"validates a zip with index.html in a top-level directory", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"base/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;

        [op start];
        
        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(YES);
        expect(op.indexDirPath).to.equal(@"base");
    });

    it(@"invalidates a zip without index.html", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"report.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;

        [op start];
        
        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;
    });

    it(@"invalidates a zip with index.html in a lower-level directory", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"base/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/sub/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;

        [op start];
        
        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;
    });

    it(@"invalidates a zip with root entries and non-root index.html", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"base/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"root.cruft" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;

        [op start];
        
        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;
    });

    it(@"uses the most shallow index.html", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [[given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"base/images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/sub/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]] willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/sub/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;
        
        [op start];
        
        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(YES);
        expect(op.indexDirPath).to.equal(@"");

        op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;

        [op start];

        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(YES);
        expect(op.indexDirPath).to.equal(@"");
    });

    it(@"validates multiple base dirs with root index.html", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"base1/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base2/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;

        [op start];
        
        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(YES);
        expect(op.indexDirPath).to.equal(@"");
    });

    it(@"invalidates multiple base dirs without root index.html", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"base1/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base2/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base0/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;

        [op start];

        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isLayoutValid).to.equal(NO);
        expect(op.indexDirPath).to.beNil;
    });

});

SpecEnd
