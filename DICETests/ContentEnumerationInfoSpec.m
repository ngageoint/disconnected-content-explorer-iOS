//
//  ContentEnumerationInfoSpec.m
//  DICE
//
//  Created by Robert St. John on 10/11/16.
//  Copyright 2016 mil.nga. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ReportType.h"


SpecBegin(ContentEnumerationInfo)

describe(@"ContentEnumerationInfo", ^{


    __block ContentEnumerationInfo *info;

    beforeAll(^{

    });

    beforeEach(^{
        info = [[ContentEnumerationInfo alloc] init];
    });

    it(@"accumulates the total content size and entry count", ^{
        expect(info.totalContentSize).to.equal(0);
        expect(info.entryCount).to.equal(0);

        [info addInfoForEntryPath:@"whatever/thing" size:211];
        [info addInfoForEntryPath:@"a_dir/" size:0];
        [info addInfoForEntryPath:@"a_dir/another_thing" size:789];

        expect(info.totalContentSize).to.equal(1000);
        expect(info.entryCount).to.equal(3);
    });

    it(@"begins with no base dir", ^{
        expect(info.baseDir).to.beNil();
        expect(info.hasBaseDir).to.equal(NO);
    });

    it(@"identifies a single base dir", ^{

        [info addInfoForEntryPath:@"base/" size:0];

        expect(info.baseDir).to.equal(@"base");
        expect(info.hasBaseDir).to.equal(YES);
    });

    it(@"identifies a base dir with contents", ^{

        [info addInfoForEntryPath:@"base/" size:0];
        [info addInfoForEntryPath:@"base/contents.txt" size:10];
        [info addInfoForEntryPath:@"base/more.html" size:100];

        expect(info.hasBaseDir).to.equal(YES);
        expect(info.baseDir).to.equal(@"base");
    });

    it(@"has no base dir after identifying a base dir then another root entry", ^{

        [info addInfoForEntryPath:@"fake_base/" size:0];
        [info addInfoForEntryPath:@"fake_base/contents" size:100];

        expect(info.hasBaseDir).to.equal(YES);
        expect(info.baseDir).to.equal(@"fake_base");

        [info addInfoForEntryPath:@"base_invalidator" size:1];

        expect(info.hasBaseDir).to.equal(NO);
        expect(info.baseDir).to.equal(@"");
    });

    afterEach(^{

    });

    afterAll(^{

    });
});

SpecEnd
