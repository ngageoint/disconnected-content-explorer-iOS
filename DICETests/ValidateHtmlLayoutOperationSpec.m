//
//  ValidateHtmlLayoutOperationSpec.m
//  DICE
//
//  Created by Robert St. John on 7/18/16.
//  Copyright 2016 mil.nga. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ValidateHtmlLayoutOperation.h"
#import "FileTree.h"
#import "ZipFile.h"
#import "FileInZipInfo.h"


@interface VHLOSFileListingEntry : NSObject <FileListingEntry>

+ (NSArray<VHLOSFileListingEntry *> *)createFromPathsAndSizes:(NSArray *)pathsAndSizes;
+ (instancetype)createWithPath:(NSString *)path size:(NSUInteger)size;

@property NSString *fileListing_path;
@property NSUInteger fileListing_size;

- (instancetype)initWithPath:(NSString *)path size:(NSUInteger)size;

@end

@implementation VHLOSFileListingEntry
+ (NSArray<VHLOSFileListingEntry *> *)createFromPathsAndSizes:(NSArray *)pathsAndSizes
{
    NSMutableArray<VHLOSFileListingEntry *> *entries = [NSMutableArray array];
    for (NSUInteger i = 0; i < pathsAndSizes.count; i += 2) {
        NSString *path = pathsAndSizes[i];
        NSNumber *size = pathsAndSizes[i + 1];
        [entries addObject:[VHLOSFileListingEntry createWithPath:path size:size.unsignedIntegerValue]];
    }
    return [NSArray arrayWithArray:entries];
}
+ (instancetype)createWithPath:(NSString *)path size:(NSUInteger)size
{
    return [[VHLOSFileListingEntry alloc] initWithPath:path size:size];
}
- (instancetype)initWithPath:(NSString *)path size:(NSUInteger)size
{
    if (!(self = [super init])) {
        return nil;
    }
    _fileListing_path = path;
    _fileListing_size = size;
    return self;
}
@end


@interface VHLOSFileListing : NSEnumerator

+ (instancetype)listingWithEntries:(NSArray *)pathsAndSizes;

@property NSEnumerator<VHLOSFileListingEntry *> *entries;

- (instancetype)initWithEntries:(NSArray<VHLOSFileListingEntry *> *)entries;

@end

@implementation VHLOSFileListing
+ (instancetype)listingWithEntries:(NSArray *)pathsAndSizes
{
    VHLOSFileListing *listing = [[VHLOSFileListing alloc] initWithEntries:[VHLOSFileListingEntry createFromPathsAndSizes:pathsAndSizes]];
    return listing;
}
- (instancetype)initWithEntries:(NSArray<VHLOSFileListingEntry *> *)entries
{
    if (!(self = [super init])) {
        return nil;
    }

    _entries = [entries objectEnumerator];

    return self;
}
- (VHLOSFileListingEntry *)nextObject
{
    return self.entries.nextObject;
}
- (NSArray<VHLOSFileListingEntry *> *)allObjects
{
    return self.entries.allObjects;
}
@end


SpecBegin(ValidateHtmlLayoutOperation)

    describe(@"ValidateHtmlLayoutOperation", ^{

        it(@"validates a zip with index.html at the root level", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"images/", @0,
                @"images/favicon.gif", @0,
                @"index.html", @0
            ]];
            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(YES);
            expect(op.indexDirPath).to.equal(@"");
        });

        it(@"validates a zip with index.html in a top-level directory", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"base/", @0,
                @"base/images/", @0,
                @"base/images/favicon.gif", @0,
                @"base/index.html", @0
            ]];
            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(YES);
            expect(op.indexDirPath).to.equal(@"base");
        });

        it(@"invalidates a zip without index.html", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"images/", @0,
                @"images/favicon.gif", @0,
                @"report.html", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;
        });

        it(@"invalidates a zip with index.html in a lower-level directory", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"base/", @0,
                @"base/images/", @0,
                @"base/images/favicon.gif", @0,
                @"base/sub/index.html", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;
        });

        it(@"invalidates a zip with root entries and non-root index.html", ^{
                NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"base/", @0,
                @"base/images/", @0,
                @"base/images/favicon.gif", @0,
                @"base/index.html", @0,
                @"root.cruft", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;
        });

        it(@"uses the most shallow index.html", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"base/", @0,
                @"base/images/", @0,
                @"base/images/favicon.gif", @0,
                @"base/sub/", @0,
                @"base/sub/index.html", @0,
                @"index.html", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(YES);
            expect(op.indexDirPath).to.equal(@"");
            
            files = [VHLOSFileListing listingWithEntries:@[
                @"index.html", @0,
                @"base/", @0,
                @"base/images/", @0,
                @"base/images/favicon.gif", @0,
                @"base/sub/", @0,
                @"base/sub/index.html", @0,
            ]];
            op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(YES);
            expect(op.indexDirPath).to.equal(@"");
        });

        it(@"validates multiple base dirs with root index.html", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"base1/", @0,
                @"base2/", @0,
                @"base1/index.html", @0,
                @"base2/index.html", @0,
                @"index.html", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(YES);
            expect(op.indexDirPath).to.equal(@"");
        });

        it(@"invalidates multiple base dirs without root index.html", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"base1/", @0,
                @"base2/", @0,
                @"base0/", @0,
                @"base1/index.html", @0,
                @"base2/index.html", @0,
                @"base0/index.html", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;

            [op start];

            expect(op.isFinished).to.equal(YES);
            expect(op.isCancelled).to.equal(NO);
            expect(op.isLayoutValid).to.equal(NO);
            expect(op.indexDirPath).to.beNil;
        });

        it(@"sets the report descriptor url when available next to index.html", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"base/", @0,
                @"base/metadata.json", @0,
                @"base/index.html", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;

            [op start];

            expect(op.hasDescriptor).to.equal(YES);
            expect(op.descriptorPath).to.equal(@"base/metadata.json");
        });

        it(@"sets the report descriptor url when available next to index.html without base dir", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"metadata.json", @0,
                @"index.html", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;

            [op start];

            expect(op.hasDescriptor).to.equal(YES);
            expect(op.descriptorPath).to.equal(@"metadata.json");
        });

        it(@"does not set the report descriptor if not next to index.html", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"index.html", @0,
                @"sub/", @0,
                @"sub/metadata.json", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;

            [op start];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;
        });


        it(@"does not set the report descriptor if not available", ^{
            NSEnumerator<id<FileListingEntry>> *files = [VHLOSFileListing listingWithEntries:@[
                @"index.html", @0,
                @"sub/", @0,
                @"sub/other.json", @0,
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:files];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;

            [op start];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;
        });
    });

SpecEnd
