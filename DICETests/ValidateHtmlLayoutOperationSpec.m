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
#import "Objective-Zip.h"
#import "OZFileInZipInfo+Internals.h"


SpecBegin(ValidateHtmlLayoutOperation)

    describe(@"ValidateHtmlLayoutOperation", ^{

        it(@"validates a zip with index.html at the root level", ^{
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"images/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"images/favicon.gif" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"base/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"images/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"images/favicon.gif" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"report.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"base/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/sub/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"base/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"root.cruft" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            OZZipFile *zipFile = mock([OZZipFile class]);
            [[given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"base/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/sub/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/sub/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            ]] willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/images/favicon.gif" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/sub/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/sub/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"base1/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base2/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base1/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base2/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"base1/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base2/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base0/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base1/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base2/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base0/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"base/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/metadata.json" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"base/index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;

            [op start];

            expect(op.hasDescriptor).to.equal(YES);
            expect(op.descriptorPath).to.equal(@"base/metadata.json");
        });

        it(@"sets the report descriptor url when available next to index.html without base dir", ^{
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"metadata.json" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;

            [op start];

            expect(op.hasDescriptor).to.equal(YES);
            expect(op.descriptorPath).to.equal(@"metadata.json");
        });

        it(@"does not set the report descriptor if not next to index.html", ^{
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"sub/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"sub/metadata.json" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
            ]];

            ValidateHtmlLayoutOperation *op = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;

            [op start];

            expect(op.hasDescriptor).to.equal(NO);
            expect(op.descriptorPath).to.beNil;
        });


        it(@"does not set the report descriptor if not available", ^{
            OZZipFile *zipFile = mock([OZZipFile class]);
            [given([zipFile listFileInZipInfos]) willReturn:@[
                [[OZFileInZipInfo alloc] initWithName:@"index.html" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"sub/" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
                [[OZFileInZipInfo alloc] initWithName:@"sub/other.json" length:0 level:OZZipCompressionLevelNone crypted:NO size:0 date:nil crc32:0],
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
