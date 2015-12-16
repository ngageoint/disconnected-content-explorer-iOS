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
#import "FileOperations.h"
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

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(YES);
    });

    it(@"could not handle a directory without index.html", ^{
        NSURL *dirPath = [reportsDir URLByAppendingPathComponent:@"test_reports"];
        NSURL *indexPath = [reportsDir URLByAppendingPathComponent:@"index.html"];

        [given([fileManager attributesOfItemAtPath:dirPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [given([fileManager attributesOfItemAtPath:indexPath.path error:nil]) willReturn:nil];

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(NO);
    });

    it(@"could not handle a directory when index.html is a directory", ^{
        NSURL *dirPath = [reportsDir URLByAppendingPathComponent:@"test_reports"];
        NSURL *indexPath = [reportsDir URLByAppendingPathComponent:@"index.html"];

        [given([fileManager attributesOfItemAtPath:dirPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [given([fileManager attributesOfItemAtPath:indexPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(NO);
    });

    it(@"could handle a zip file", ^{
        NSURL *zipPath = [reportsDir URLByAppendingPathComponent:@"test_report.zip"];

        [given([fileManager attributesOfItemAtPath:zipPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldHandleFile:zipPath]).to.equal(YES);
    });

    it(@"could handle an html file", ^{
        NSURL *htmlPath = [reportsDir URLByAppendingPathComponent:@"test_report.html"];

        [given([fileManager attributesOfItemAtPath:htmlPath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldHandleFile:htmlPath]).to.equal(YES);
    });

    it(@"could not handle something else", ^{
        NSURL *filePath = [reportsDir URLByAppendingPathComponent:@"test_report.txt"];

        [given([fileManager attributesOfItemAtPath:filePath.path error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldHandleFile:filePath]).to.equal(NO);
    });

    it(@"could not handle a non-regular file or non-directory", ^{
        NSURL *filePath = [reportsDir URLByAppendingPathComponent:@"i_dunno"];

        [given([fileManager attributesOfItemAtPath:filePath.path error:nil]) willReturn:@{NSFileType: NSFileTypeSocket}];

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
            [[FileInZipInfo alloc] initWithName:@"base/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/sub/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/sub/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]] willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/sub/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            [[FileInZipInfo alloc] initWithName:@"base1/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base2/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            [[FileInZipInfo alloc] initWithName:@"base1/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base2/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base0/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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

    it(@"sets the report descriptor url when available next to index.html", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"base/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/metadata.json" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"base/index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.hasDescriptor).to.equal(NO);
        expect(op.descriptorPath).to.beNil;

        [op start];

        expect(op.hasDescriptor).to.equal(YES);
        expect(op.descriptorPath).to.equal(@"base/metadata.json");
    });

    it(@"sets the report descriptor url when available next to index.html without base dir", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"metadata.json" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.hasDescriptor).to.equal(NO);
        expect(op.descriptorPath).to.beNil;
        
        [op start];
        
        expect(op.hasDescriptor).to.equal(YES);
        expect(op.descriptorPath).to.equal(@"metadata.json");
    });

    it(@"does not set the report descriptor if not next to index.html", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"sub/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"sub/metadata.json" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.hasDescriptor).to.equal(NO);
        expect(op.descriptorPath).to.beNil;
        
        [op start];
        
        expect(op.hasDescriptor).to.equal(NO);
        expect(op.descriptorPath).to.beNil;
    });


    it(@"does not set the report descriptor if not available", ^{
        ZipFile *zipFile = mock([ZipFile class]);
        [given([zipFile listFileInZipInfos]) willReturn:@[
            [[FileInZipInfo alloc] initWithName:@"index.html" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"sub/" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            [[FileInZipInfo alloc] initWithName:@"sub/other.json" length:0 level:ZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
        ]];

        ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

        expect(op.hasDescriptor).to.equal(NO);
        expect(op.descriptorPath).to.beNil;
        
        [op start];
        
        expect(op.hasDescriptor).to.equal(NO);
        expect(op.descriptorPath).to.beNil;
    });
});

SpecEnd
