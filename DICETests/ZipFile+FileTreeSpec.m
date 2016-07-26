//
//  ZipFile+FileTreeSpec.m.m
//  DICE
//
//  Created by Robert St. John on 7/25/16.
//  Copyright 2016 mil.nga. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ZipFile+FileTree.h"
#import "Objective-Zip.h"


SpecBegin(ZipFileFileTree)

describe(@"ZipFile+FileTree", ^{

    __block NSBundle *bundle;

    beforeAll(^{

    });

    beforeEach(^{
        bundle = [NSBundle bundleForClass:[ZipFileFileTreeSpec class]];
    });

    it(@"can enumerate multiple zip file entries", ^{
        NSString *zipPath = [bundle pathForResource:@"10x128_bytes" ofType:@"zip"];
        OZZipFile *zip = [[OZZipFile alloc] initWithFileName:zipPath mode:OZZipFileModeUnzip];
        NSEnumerator<id<FileListingEntry>> *entries = [zip fileTree_enumerateFiles];
        NSArray *infoList = [zip listFileInZipInfos];
        NSUInteger i = 0;

        expect(infoList.count).to.equal(10);

        for (id<FileListingEntry> entry in entries) {
            OZFileInZipInfo *info = infoList[i];
            expect([entry fileListing_path]).to.equal(info.name);
            expect([entry fileListing_size]).to.equal(info.length);
            i += 1;
        }
        expect(i).to.equal(infoList.count);

        id<FileListingEntry> entry;
        entries = [zip fileTree_enumerateFiles];
        i = 0;
        while ((entry = entries.nextObject) != nil) {
            OZFileInZipInfo *info = infoList[i];
            expect([entry fileListing_path]).to.equal(info.name);
            expect([entry fileListing_size]).to.equal(info.length);
            i += 1;
        }
        expect(i).to.equal(infoList.count);

        [zip close];
    });

    it(@"can enumerate one zip file entry", ^{
        NSString *zipPath = [bundle pathForResource:@"single_entry" ofType:@"zip"];
        OZZipFile *zip = [[OZZipFile alloc] initWithFileName:zipPath mode:OZZipFileModeUnzip];
        NSEnumerator<id<FileListingEntry>> *entries = [zip fileTree_enumerateFiles];
        NSArray *infoList = [zip listFileInZipInfos];
        NSUInteger i = 0;

        expect(infoList.count).to.equal(1);

        // ensure fast enumeration
        for (id<FileListingEntry> entry in entries) {
            OZFileInZipInfo *info = infoList[i];
            expect([entry fileListing_path]).to.equal(info.name);
            expect([entry fileListing_size]).to.equal(info.length);
            i += 1;
        }
        expect(i).to.equal(infoList.count);

        entries = [zip fileTree_enumerateFiles];
        id<FileListingEntry> entry = entries.nextObject;
        expect([entry fileListing_path]).to.equal(@"8192_bytes.dat");
        expect([entry fileListing_size]).to.equal(8192);
        expect(entries.nextObject).to.beNil;

        [zip close];
    });

    it(@"raises an error when zip file is not unzip in mode", ^{
        NSString *zipPath = [bundle pathForResource:@"single_entry" ofType:@"zip"];
        NSString *zipDir = [zipPath stringByDeletingLastPathComponent];
        NSString *newZipPath = [zipDir stringByAppendingPathComponent:@"new_zip_file.zip"];
        OZZipFile *zip = [[OZZipFile alloc] initWithFileName:[zipDir stringByAppendingPathComponent:@"new_zip_file.zip"] mode:OZZipFileModeCreate];
        expect(^{ [zip fileTree_enumerateFiles]; }).to.raise(@"OZZipException");

        [zip close];
        [[NSFileManager defaultManager] removeItemAtPath:newZipPath error:nil];

        zip = [[OZZipFile alloc] initWithFileName:zipPath mode:OZZipFileModeAppend];
        expect(^{ [zip fileTree_enumerateFiles]; }).to.raise(@"OZZipException");
        [zip close];
    });

    afterEach(^{

    });

    afterAll(^{

    });
});

SpecEnd
