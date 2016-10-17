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
#import "OZZipException.h"
#import "UnzipOperation.h"
#import "NSOperation+Blockable.h"
#import "DICEOZZipFileArchive.h"
#import "TestDICEArchive.h"
#import "OZZipException+Internals.h"
#import "MKTOngoingStubbing.h"
#import "JGMethodSwizzler.h"


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

    afterEach(^{

    });

    afterAll(^{

    });

    it(@"it throws an exception if zip file is nil", ^{
        __block UnzipOperation *op;

        expect(^{
            op = [[UnzipOperation alloc] initWithArchive:nil destDir:[NSURL URLWithString:@"/some/dir"] fileManager:[NSFileManager defaultManager]];
        }).to.raiseWithReason(@"IllegalArgumentException", @"archive is nil");

        expect(op).to.beNil();
    });

    it(@"is not ready until dest dir is set", ^{
        id<DICEArchive> archive = mockProtocol(@protocol(DICEArchive));
        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:archive destDir:nil fileManager:[NSFileManager defaultManager]];

        id observer = mock([NSObject class]);

        [op addObserver:observer forKeyPath:@"isReady" options:NSKeyValueObservingOptionPrior context:NULL];
        [op addObserver:observer forKeyPath:@"destDir" options:NSKeyValueObservingOptionPrior context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.destDir).to.beNil();

        op.destDir = [NSURL URLWithString:@"/reports_dir"];

        expect(op.ready).to.equal(YES);

        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL];
        [verify(observer) observeValueForKeyPath:@"destDir" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL];
        [verify(observer) observeValueForKeyPath:@"destDir" ofObject:op change:isNot(hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES)) context:NULL];
        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:isNot(hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES)) context:NULL];

        stopMocking(observer);
        stopMocking(archive);
    });

    it(@"is not ready until dependencies are finished", ^{
        id<DICEArchive> archive = mockProtocol(@protocol(DICEArchive));
        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:archive destDir:[NSURL URLWithString:@"/some/dir"] fileManager:[NSFileManager defaultManager]];
        NSOperation *holdup = [[NSOperation alloc] init];
        [op addDependency:holdup];

        expect(op.ready).to.equal(NO);

        [holdup start];

        assertWithTimeout(1.0, thatEventually(@(holdup.isFinished && op.isReady)), isTrue());

        stopMocking(archive);
    });

    it(@"is ready if cancelled before executing", ^{
        id<DICEArchive> archive = mockProtocol(@protocol(DICEArchive));
        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:archive destDir:nil fileManager:[NSFileManager defaultManager]];
        id observer = mock([NSObject class]);
        [op addObserver:observer forKeyPath:@"isReady" options:0 context:NULL];

        expect(op.isReady).to.equal(NO);

        [op cancel];

        expect(op.isReady).to.equal(YES);
        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:anything() context:NULL];

        stopMocking(archive);
    });

    it(@"throws an exception when dest dir change is attempted while executing", ^{
        id<DICEArchive> archive = mockProtocol(@protocol(DICEArchive));
        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:archive destDir:[NSURL URLWithString:@"/tmp/"] fileManager:[NSFileManager defaultManager]];
        [op block];

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        expect(^{
            op.destDir = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.destDir.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change destDir after UnzipOperation has started");

        [op unblock];

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());

        expect(op.destDir).to.equal([NSURL URLWithString:@"/tmp/"]);

        stopMocking(archive);
    });

    it(@"unzips with base dir", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSURL *zipFilePath = [bundle URLForResource:@"test_base_dir" withExtension:@"zip"];
        DICEOZZipFileArchive *archive = [[DICEOZZipFileArchive alloc] initWithArchivePath:zipFilePath archiveUti:NULL];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:archive destDir:destDir fileManager:[NSFileManager defaultManager]];
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

            expect(attrs).notTo.beNil();
            assertThat(attrs, hasEntry(NSFileModificationDate, modDate));
            void (^verifyEntryExpectations)(NSURL *entry, NSDictionary *attrs) = expectedContents[entry];

            expect(verifyEntryExpectations).notTo.beNil();
            verifyEntryExpectations(entry, attrs);

            [expectedContents removeObjectForKey:entry];
        }

        expect(expectedContents.count).to.equal(0);
    });

    it(@"unzips without base dir", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSURL *zipFilePath = [bundle URLForResource:@"test_no_base_dir" withExtension:@"zip"];
        DICEOZZipFileArchive *zipFile = [[DICEOZZipFileArchive alloc] initWithArchivePath:zipFilePath archiveUti:NULL];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];
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

            expect(attrs).notTo.beNil();
            assertThat(attrs, hasEntry(NSFileModificationDate, modDate));
            void (^verifyEntryExpectations)(NSURL *entry, NSDictionary *attrs) = expectedContents[entry];

            expect(verifyEntryExpectations).notTo.beNil();
            verifyEntryExpectations(entry, attrs);

            [expectedContents removeObjectForKey:entry];
        }

        expect(expectedContents.count).to.equal(0);
    });

    it(@"notifies the delegate on the operation thread", ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSBundle *bundle = [NSBundle bundleForClass:[UnzipOperationSpec class]];
        NSURL *zipFilePath = [bundle URLForResource:@"10x128_bytes" withExtension:@"zip"];
        DICEOZZipFileArchive *zipFile = [[DICEOZZipFileArchive alloc] initWithArchivePath:zipFilePath archiveUti:NULL];
        NSURL *destDir = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[[NSUUID UUID] UUIDString]];

        [fm createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

        id<UnzipDelegate> unzipDelegate = mockProtocol(@protocol(UnzipDelegate));
        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:zipFile destDir:destDir fileManager:[NSFileManager defaultManager]];
        op.buffer = [NSMutableData dataWithLength:64];
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

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());

        expect(wasMainThread).to.equal(NO);
        expect(percentUpdates.count).to.equal(20);
        [percentUpdates enumerateObjectsUsingBlock:^(NSNumber *percent, NSUInteger idx, BOOL *stop) {
            expect(percent.unsignedIntegerValue).to.equal((idx + 1) * 5);
        }];

        [verify(unzipDelegate) unzipOperationDidFinish:sameInstance(op)];
    });

    it(@"is unsuccessful when the file for an entry cannot be created", ^{
        TestDICEArchive *zipFile = [TestDICEArchive archiveWithEntries:@[
            [TestDICEArchiveEntry entryWithName:@"index.html" sizeInArchive:128 sizeExtracted:256]
        ] archiveUrl:[NSURL fileURLWithPath:@"/dice/test.zip"] archiveUti:NULL];
        NSURL *destDir = [NSURL fileURLWithPath:@"/tmp/test"];
        NSFileManager *fileManager = mock([NSFileManager class]);

        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:zipFile destDir:destDir fileManager:fileManager];

        [zipFile enqueueError:[NSError errorWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"test error"}]];

        [given([fileManager createFileAtPath:@"/tmp/test/index.html" contents:nil attributes:nil]) willReturnBool:NO];

        [op start];

        expect(op.wasSuccessful).to.equal(NO);
        expect(op.errorMessage).to.equal(@"Failed to create file to extract archive entry index.html");

        stopMocking(fileManager);
    });

    it(@"is unsuccessful when the file handle for an entry cannot be opened for writing", ^{
        TestDICEArchive *zipFile = [TestDICEArchive archiveWithEntries:@[
            [TestDICEArchiveEntry entryWithName:@"index.html" sizeInArchive:128 sizeExtracted:256]
        ] archiveUrl:[NSURL fileURLWithPath:@"/dice/test.zip"] archiveUti:NULL];
        NSURL *destDir = [NSURL fileURLWithPath:@"/tmp/test"];
        NSFileManager *fileManager = mock([NSFileManager class]);

        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:zipFile destDir:destDir fileManager:fileManager];

        [given([fileManager createFileAtPath:@"/tmp/test/index.html" contents:nil attributes:nil]) willReturnBool:YES];

        NSError *error = [NSError errorWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"test error"}];
        [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
            return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                *errOut = error;
                return nil;
            };
        }];

        [op start];

        expect(op.wasSuccessful).to.equal(NO);
        expect(op.errorMessage).to.equal(@"Failed to open file for writing archive entry index.html: test error");

        stopMocking(fileManager);
        deswizzleAll();
    });

    it(@"is unsuccessful when an entry cannot be opened", ^{
        TestDICEArchive *zipFile = [TestDICEArchive archiveWithEntries:@[
            [TestDICEArchiveEntry entryWithName:@"index.html" sizeInArchive:128 sizeExtracted:256]
        ] archiveUrl:[NSURL fileURLWithPath:@"/dice/test.zip"] archiveUti:NULL];
        NSURL *destDir = [NSURL fileURLWithPath:@"/tmp/test"];
        NSFileManager *fileManager = mock([NSFileManager class]);

        UnzipOperation *op = [[UnzipOperation alloc] initWithArchive:zipFile destDir:destDir fileManager:fileManager];

        [zipFile calculateArchiveSizeExtractedWithError:nil];
        [zipFile enqueueError:[NSError errorWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"test error"}]];

        [given([fileManager createFileAtPath:@"/tmp/test/index.html" contents:nil attributes:nil]) willReturnBool:YES];
        NSFileHandle *stdout = [NSFileHandle fileHandleWithStandardOutput];
        [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
            return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                return stdout;
            };
        }];

        [op start];

        expect(op.wasSuccessful).to.equal(NO);
        expect(op.errorMessage).to.equal(@"Failed to read archive entry index.html: test error");

        stopMocking(fileManager);
        deswizzleAll();
    });

});

SpecEnd
