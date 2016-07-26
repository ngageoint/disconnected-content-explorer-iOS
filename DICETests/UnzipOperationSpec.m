//
//  UnzipOperationSpec.m
//  DICE
//
//  Created by Robert St. John on 7/31/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "OZZipFile+Standard.h"
#import "OZZipException+Internals.h"
#import "UnzipOperation.h"
#import "NSOperation+Blockable.h"


@interface SpecificException : NSException

- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo;

@end


@interface ThrowException : NSObject

- (void)throwException;

@end


@interface ExceptionTest : NSOperation

@property ThrowException *thrower;
@property NSException *exception;

- (instancetype)initWithThrower:(ThrowException *)thrower;

- (void)catchException;

@end


@implementation ExceptionTest

- (instancetype)initWithThrower:(ThrowException *)thrower
{
    self = [super init];
    _thrower = thrower;
    return self;
}

- (void)main
{
    @autoreleasepool {
        @try {
            [self doIt];
        }
        @catch (SpecificException *exception) {
            self.exception = exception;
        }
        @catch (OZZipException *exception) {
            self.exception = exception;
        }
        @catch (NSException *exception) {
            self.exception = exception;
        }
        @finally {
            self.thrower = nil;
        }
    }
}

- (void)catchException
{
    @autoreleasepool {
        @try {
            [self doIt];
        }
        @catch (SpecificException *exception) {
            self.exception = exception;
        }
        @catch (OZZipException *exception) {
            self.exception = exception;
        }
        @catch (NSException *exception) {
            self.exception = exception;
        }
        @finally {
            self.thrower = nil;
        }
    }
}

- (void)doIt
{
    [self.thrower throwException];
}

@end


@implementation ThrowException

- (instancetype)init
{
    return (self = [super init]);
}

- (void)throwException
{

}

@end


@implementation SpecificException

- (id)initWithName:(NSString *)aName reason:(NSString *)aReason userInfo:(NSDictionary *)aUserInfo
{
    return (self = [super initWithName:aName reason:aReason userInfo:aUserInfo]);
}

@end


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
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:mock([OZZipFile class]) destDir:nil fileManager:[NSFileManager defaultManager]];

        id observer = mock([NSObject class]);

        [op addObserver:observer forKeyPath:@"isReady" options:NSKeyValueObservingOptionPrior context:NULL];
        [op addObserver:observer forKeyPath:@"destDir" options:NSKeyValueObservingOptionPrior context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.destDir).to.beNil;

        op.destDir = [NSURL URLWithString:@"/reports_dir"];

        expect(op.ready).to.equal(YES);

        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL];
        [verify(observer) observeValueForKeyPath:@"destDir" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL];
        [verify(observer) observeValueForKeyPath:@"destDir" ofObject:op change:isNot(hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES)) context:NULL];
        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:isNot(hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES)) context:NULL];

        stopMocking(observer);
    });

    it(@"is not ready until dependencies are finished", ^{
        OZZipFile *zipFile = mock([OZZipFile class]);
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:[NSURL URLWithString:@"/some/dir"] fileManager:[NSFileManager defaultManager]];
        NSOperation *holdup = [[NSOperation alloc] init];
        [op addDependency:holdup];

        expect(op.ready).to.equal(NO);

        [holdup start];

        assertWithTimeout(1.0, thatEventually(@(holdup.isFinished && op.isReady)), isTrue());

        stopMocking(zipFile);
    });

    it(@"is ready if cancelled before executing", ^{
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:mock([OZZipFile class]) destDir:nil fileManager:[NSFileManager defaultManager]];
        id observer = mock([NSObject class]);
        [op addObserver:observer forKeyPath:@"isReady" options:0 context:NULL];

        expect(op.isReady).to.equal(NO);

        [op cancel];

        expect(op.isReady).to.equal(YES);
        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:anything() context:NULL];
    });

    it(@"throws an exception when dest dir change is attempted while executing", ^{
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:mock([OZZipFile class]) destDir:[NSURL URLWithString:@"/tmp/"] fileManager:[NSFileManager defaultManager]];
        [op block];
        [op performSelectorInBackground:@selector(start) withObject:nil];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        expect(^{
            op.destDir = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.destDir.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change destDir after UnzipOperation has started");

        [op unblock];
        [op waitUntilFinished];

        expect(op.destDir).to.equal([NSURL URLWithString:@"/tmp/"]);
    });

    it(@"unzips with base dir", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSString *zipFilePath = [bundle pathForResource:@"test_base_dir" ofType:@"zip"];
        OZZipFile *zipFile = [[OZZipFile alloc] initWithFileName:zipFilePath mode:OZZipFileModeUnzip];
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
        NSDate *modDate = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] dateFromComponents:comps];

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
        OZZipFile *zipFile = [[OZZipFile alloc] initWithFileName:zipFilePath mode:OZZipFileModeUnzip];
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
        NSDate *modDate = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar] dateFromComponents:comps];

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

    it(@"reports unzip progress on the main thread for percentage changes", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSString *zipFilePath = [bundle pathForResource:@"10x128_bytes" ofType:@"zip"];
        OZZipFile *zipFile = [[OZZipFile alloc] initWithFileName:zipFilePath mode:OZZipFileModeUnzip];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        id<UnzipDelegate> unzipDelegate = mockProtocol(@protocol(UnzipDelegate));
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];
        op.bufferSize = 64;
        op.delegate = unzipDelegate;

        __block BOOL wasMainThread = YES;
        NSMutableArray *percentUpdates = [NSMutableArray array];
        [[givenVoid([unzipDelegate unzipOperation:op didUpdatePercentComplete:0]) withMatcher:anything() forArgument:1] willDo:^id(NSInvocation *invocation) {
            wasMainThread = wasMainThread && [NSThread currentThread] == [NSThread mainThread];
            NSUInteger percent = 0;
            [invocation getArgument:&percent atIndex:3];
            [percentUpdates addObject:@(percent)];
            return nil;
        }];

        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [op start];
        });

        assertWithTimeout(1.0, thatEventually(@(percentUpdates.count)), is(@20));

        expect(wasMainThread).to.equal(YES);
        expect(percentUpdates.count).to.equal(20);
        [percentUpdates enumerateObjectsUsingBlock:^(NSNumber *percent, NSUInteger idx, BOOL *stop) {
            expect(percent.unsignedIntegerValue).to.equal((idx + 1) * 5);
        }];
    });

    it(@"is unsuccessful when unzipping raises an exception", ^{
        OZZipFile *zipFile = mock([OZZipFile class]);
        OZZipException *zipError = [[OZZipException alloc] initWithError:99 reason:@"test error"];

        [givenVoid([zipFile goToFirstFileInZip]) willThrow:zipError];

        expect(zipError).to.beInstanceOf([OZZipException class]);

        NSURL *destDir = [NSURL fileURLWithPath:@"/tmp/test"];
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];

        [op start];

        expect(op.wasSuccessful).to.equal(NO);
        expect(op.errorMessage).to.equal(@"Error reading zip file: test error");
        [verify(zipFile) close];

        stopMocking(zipFile);
    });

    /*
     These tests are for a weird condition in which the catch block 
     for OZZipException gets skipped and drops through to NSException.
     Maybe we can revisit this later, but for now, just check the 
     name on the NSException that actually gets caught.

     TODO: now with objective-zip 1.x there is NSError** style error handling available - should switch to that
     */

    it(@"catches OZZipException", ^{
        OZZipFile *zipFile = mock([OZZipFile class]);
        OZZipException *ze = [[OZZipException alloc] initWithError:99 reason:@"test error"];
        [givenVoid([zipFile goToFirstFileInZip]) willThrow:ze];

        @try {
            [zipFile goToFirstFileInZip];
        }
        @catch (OZZipException *exception) {
            expect(exception).to.beInstanceOf([OZZipException class]);
            return;
        }

        failure(@"did not catch exception");
    });

    it(@"can mock throw exceptions", ^{
        ThrowException *thrower = mock([ThrowException class]);
        ExceptionTest *test = [[ExceptionTest alloc] initWithThrower:thrower];

        OZZipException *zipError = [[OZZipException alloc] initWithError:99 reason:@"test error"];
        NSException *err = [[SpecificException alloc] initWithName:@"Test" reason:@"Testing" userInfo:nil];
        [givenVoid([thrower throwException]) willThrow:zipError];

        [test start];

        expect([test.exception class]).to.equal([OZZipException class]);

        stopMocking(thrower);
    });

    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
