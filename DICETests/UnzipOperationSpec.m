//
//  UnzipOperationSpec.m
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

#import "UnzipOperation.h"


SpecBegin(UnzipOperation)

describe(@"UnzipOperation", ^{

    beforeAll(^{

    });
    
    beforeEach(^{

    });

    it(@"it throws an exception if zip file is nil", ^{
        __block UnzipOperation *op;

        expect(^{
            op = [[UnzipOperation alloc] initWithZipFile:nil destDir:[NSURL URLWithString:@"/some/dir"] fileManager:[NSFileManager defaultManager]];
        }).to.raiseWithReason(@"IllegalArgumentException", @"zipFile is nil");

        expect(op).to.beNil;
    });

    it(@"is not ready until dest dir is set", ^{
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:OCMClassMock([ZipFile class]) destDir:nil fileManager:[NSFileManager defaultManager]];

        id observer = observer = OCMStrictClassMock([NSObject class]);
        [observer setExpectationOrderMatters:YES];

        OCMExpect([observer observeValueForKeyPath:@"isReady" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"destDir" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"destDir" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"isReady" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);

        [op addObserver:observer forKeyPath:@"isReady" options:NSKeyValueObservingOptionPrior context:NULL];
        [op addObserver:observer forKeyPath:@"destDir" options:NSKeyValueObservingOptionPrior context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.destDir).to.beNil;

        op.destDir = [NSURL URLWithString:@"/reports_dir"];

        expect(op.ready).to.equal(YES);
        OCMVerifyAll(observer);
    });

    it(@"is not ready until dependencies are finished", ^{
        ZipFile *zipFile = OCMClassMock([ZipFile class]);
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:[NSURL URLWithString:@"/some/dir"] fileManager:[NSFileManager defaultManager]];
        NSOperation *holdup = [[NSOperation alloc] init];
        [op addDependency:holdup];

        expect(op.ready).to.equal(NO);

        [holdup start];

        waitUntil(^(DoneCallback done) {
            if (holdup.finished) {
                done();
            }
        });

        expect(op.ready).to.equal(YES);
    });

    it(@"throws an exception when dest dir change is attempted while executing", ^{
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:OCMClassMock([ZipFile class]) destDir:[NSURL URLWithString:@"/tmp/"] fileManager:[NSFileManager defaultManager]];
        UnzipOperation *mockOp = OCMPartialMock(op);
        OCMStub([mockOp isExecuting]).andReturn(YES);

        expect(^{
            op.destDir = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.destDir.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change destDir after UnzipOperation has started");

        expect(op.destDir).to.equal([NSURL URLWithString:@"/tmp/"]);
    });

    it(@"unzips with base dir", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSString *zipFilePath = [bundle pathForResource:@"test_base_dir" ofType:@"zip"];
        ZipFile *zipFile = [[ZipFile alloc] initWithFileName:zipFilePath mode:ZipFileModeUnzip];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];
        [op start];

        expect(op.wasSuccessful).to.equal(YES);

        destDir = [destDir URLByAppendingPathComponent:@"test"];

        NSMutableDictionary *expectedContents = [NSMutableDictionary dictionaryWithDictionary:@{
            [destDir URLByAppendingPathComponent:@"100_zero_bytes.dat" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSData *contents = [NSData dataWithContentsOfURL:entry];
                expect(contents.length).to.equal(100);
                for (unsigned char i = 0; i < 100; i++) {
                    expect(*((char *)contents.bytes + i)).to.equal(0);
                }
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"hello.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"Hello, test!\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"empty_dir" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                NSArray *contents = [fm contentsOfDirectoryAtURL:entry includingPropertiesForKeys:nil options:0 error:nil];
                expect(contents.count).to.equal(0);
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub1" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub1/sub1.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"sub1\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"sub2" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub2/sub2.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"sub2\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
        }];

        NSDateComponents *comps = [[NSDateComponents alloc] init];
        [comps setDay:1];
        [comps setMonth:8];
        [comps setYear:2015];
        [comps setHour:12];
        [comps setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"MDT"]];
        NSDate *modDate = [[NSCalendar currentCalendar] dateFromComponents:comps];

        NSDirectoryEnumerator *extractedContents = [fm enumeratorAtURL:destDir
            includingPropertiesForKeys:@[
                NSURLIsDirectoryKey,
                NSURLIsRegularFileKey,
                NSURLContentModificationDateKey,
            ]
            options:0 errorHandler:nil];

        NSArray *allEntries = [extractedContents allObjects];
        expect(allEntries.count).to.equal(expectedContents.count);

        for (NSURL *entry in allEntries) {
            expect([fm fileExistsAtPath:entry.path]).to.equal(YES);

            NSMutableDictionary *attrs = [[fm attributesOfItemAtPath:entry.path error:nil] mutableCopy];
            attrs[@"path"] = entry.path;

            expect(attrs).notTo.beNil;
            assertThat(attrs, hasEntry(NSFileModificationDate, modDate));
            void (^verifyEntryExpectations)(NSURL *entry, NSDictionary *attrs) = expectedContents[entry];

            expect(verifyEntryExpectations).notTo.beNil;
            verifyEntryExpectations(entry, attrs);

            [expectedContents removeObjectForKey:entry];
        }

        expect(expectedContents.count).to.equal(0);
    });

    it(@"unzips without base dir", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSString *zipFilePath = [bundle pathForResource:@"test_no_base_dir" ofType:@"zip"];
        ZipFile *zipFile = [[ZipFile alloc] initWithFileName:zipFilePath mode:ZipFileModeUnzip];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];
        [op start];

        expect(op.wasSuccessful).to.equal(YES);

        NSMutableDictionary *expectedContents = [NSMutableDictionary dictionaryWithDictionary:@{
            [destDir URLByAppendingPathComponent:@"100_zero_bytes.dat" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSData *contents = [NSData dataWithContentsOfURL:entry];
                expect(contents.length).to.equal(100);
                for (unsigned char i = 0; i < 100; i++) {
                    expect(*((char *)contents.bytes + i)).to.equal(0);
                }
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"hello.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"Hello, test!\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"empty_dir" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                NSArray *contents = [fm contentsOfDirectoryAtURL:entry includingPropertiesForKeys:nil options:0 error:nil];
                expect(contents.count).to.equal(0);
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub1" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub1/sub1.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"sub1\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
            [destDir URLByAppendingPathComponent:@"sub2" isDirectory:YES]: ^(NSURL *entry, NSDictionary *attrs) {
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeDirectory));
            },
            [destDir URLByAppendingPathComponent:@"sub2/sub2.txt" isDirectory:NO]: ^(NSURL *entry, NSDictionary *attrs) {
                NSString *content = [NSString stringWithContentsOfURL:entry encoding:NSUTF8StringEncoding error:nil];
                expect(content).to.equal(@"sub2\n");
                assertThat(attrs, hasEntry(NSFileType, NSFileTypeRegular));
            },
        }];

        NSDateComponents *comps = [[NSDateComponents alloc] init];
        [comps setDay:1];
        [comps setMonth:8];
        [comps setYear:2015];
        [comps setHour:12];
        [comps setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"MDT"]];
        NSDate *modDate = [[NSCalendar currentCalendar] dateFromComponents:comps];

        NSDirectoryEnumerator *extractedContents = [fm enumeratorAtURL:destDir
            includingPropertiesForKeys:@[
                NSURLIsDirectoryKey,
                NSURLIsRegularFileKey,
                NSURLContentModificationDateKey,
            ]
            options:0 errorHandler:nil];

        NSArray *allEntries = [extractedContents allObjects];
        expect(allEntries.count).to.equal(expectedContents.count);

        for (NSURL *entry in allEntries) {
            expect([fm fileExistsAtPath:entry.path]).to.equal(YES);

            NSMutableDictionary *attrs = [[fm attributesOfItemAtPath:entry.path error:nil] mutableCopy];
            attrs[@"path"] = entry.path;

            expect(attrs).notTo.beNil;
            assertThat(attrs, hasEntry(NSFileModificationDate, modDate));
            void (^verifyEntryExpectations)(NSURL *entry, NSDictionary *attrs) = expectedContents[entry];

            expect(verifyEntryExpectations).notTo.beNil;
            verifyEntryExpectations(entry, attrs);

            [expectedContents removeObjectForKey:entry];
        }

        expect(expectedContents.count).to.equal(0);
    });

    it(@"reports unzip progress", ^{
        failure(@"unimplemented");
    });

    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
