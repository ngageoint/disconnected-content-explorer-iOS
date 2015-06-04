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

#import "ResourceTypes.h"
#import "HtmlReportType.h"


SpecBegin(ReportType)


describe(@"HtmlReportType", ^{

    NSFileManager * const fileManager = mock([NSFileManager class]);

    HtmlReportType * const htmlReportType = [[HtmlReportType alloc] initWithFileManager:fileManager];
    NSString * const reportsDir = @"/test/reports/";
    

    afterEach(^{
        [((MKTBaseMockObject *)fileManager) reset];
    });

    it(@"could handle a directory if it contains index.html", ^{
        NSString *dirPath = [reportsDir stringByAppendingPathComponent:@"test_report"];
        NSString *indexPath = [dirPath stringByAppendingPathComponent:@"index.html"];

        NSLog(@"index path: %@", indexPath);

        [given([fileManager attributesOfItemAtPath:dirPath error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [[given([fileManager fileExistsAtPath:indexPath isDirectory:nil]) withMatcher:anything() forArgument:1] willDo:^id (NSInvocation *invocation) {
            BOOL *isDirectory;
            [invocation getArgument:&isDirectory atIndex:3];
            *isDirectory = NO;
            return @YES;
        }];

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(YES);
    });

    it(@"could not handle a directory without index.html", ^{
        NSString *dirPath = [reportsDir stringByAppendingPathComponent:@"test_reports"];
        NSString *indexPath = [reportsDir stringByAppendingPathComponent:@"index.html"];

        [given([fileManager attributesOfItemAtPath:dirPath error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [[given([fileManager fileExistsAtPath:indexPath isDirectory:nil]) withMatcher:notNilValue() forArgument:1] willDo:^id (NSInvocation *invocation) {
            BOOL *isDirectory;
            [invocation getArgument:&isDirectory atIndex:3];
            *isDirectory = NO;
            return @NO;
        }];

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(NO);
    });

    it(@"could not handle a directory when index.html is a directory", ^{
        NSString *dirPath = [reportsDir stringByAppendingPathComponent:@"test_reports"];
        NSString *indexPath = [reportsDir stringByAppendingPathComponent:@"index.html"];

        [given([fileManager attributesOfItemAtPath:dirPath error:nil]) willReturn:@{NSFileType: NSFileTypeDirectory}];
        [[given([fileManager fileExistsAtPath:indexPath isDirectory:nil]) withMatcher:notNilValue() forArgument:1] willDo:^id (NSInvocation *invocation) {
            BOOL *isDirectory;
            [invocation getArgument:&isDirectory atIndex:3];
            *isDirectory = YES;
            return @YES;
        }];

        expect([htmlReportType couldHandleFile:dirPath]).to.equal(NO);
    });

    it(@"could handle a zip file", ^{
        NSString *zipPath = [reportsDir stringByAppendingPathComponent:@"test_report.zip"];

        [given([fileManager attributesOfItemAtPath:zipPath error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldHandleFile:zipPath]).to.equal(YES);
    });

    it(@"could handle an html file", ^{
        NSString *htmlPath = [reportsDir stringByAppendingPathComponent:@"test_report.html"];

        [given([fileManager attributesOfItemAtPath:htmlPath error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldHandleFile:htmlPath]).to.equal(YES);
    });

    it(@"could not handle something else", ^{
        NSString *filePath = [reportsDir stringByAppendingPathComponent:@"test_report.txt"];

        [given([fileManager attributesOfItemAtPath:filePath error:nil]) willReturn:@{NSFileType: NSFileTypeRegular}];

        expect([htmlReportType couldHandleFile:filePath]).to.equal(NO);
    });

    it(@"could not handle a non-regular file or non-directory", ^{
        NSString *filePath = [reportsDir stringByAppendingPathComponent:@"i_dunno"];

        [given([fileManager attributesOfItemAtPath:filePath error:nil]) willReturn:@{NSFileType: NSFileTypeBlockSpecial}];

        expect([htmlReportType couldHandleFile:filePath]).to.equal(NO);
    });

    describe(@"importReport from zip file", ^{

        it(@"unzips the file asynchronously", ^{
            Report *report = nil;
            [htmlReportType importReport:report];
        });

        it(@"unzips the file to a temporary directory", ^{
            failure(@"unimplemented");
        });

        it(@"leaves the zip file if an error occurs", ^{
            failure(@"unimplemented");
        });

        it(@"deletes the zip file after unzipping successfully", ^{
            failure(@"unimplemented");
        });

        it(@"reports unzip progress updates", ^{
            failure(@"unimplemented");
        });
    });

});

SpecEnd