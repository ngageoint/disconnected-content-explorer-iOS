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
#import "ValidateHtmlLayoutOperation.h"
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

SpecEnd
