//
//  ReportSpec.m
//  DICE
//
//  Created by Robert St. John on 8/11/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>

#import "Report.h"


SpecBegin(Report)

describe(@"Report", ^{
    
    beforeAll(^{

    });
    
    beforeEach(^{

    });
    
    it(@"updates report from json descriptor", ^{
        Report *report = [[Report alloc] init];

        [report setPropertiesFromJsonDescriptor:@{
            @"contentId": @"abc123",
            @"title": @"JSON Test",
            @"description": @"Test the JSON meta-data mechanism",
            @"lat": @39.8,
            @"lon": @-104.8,
            @"thumbnail": @"images/test.png",
            @"tile_thumbnail": @"images/test-tile.png",
        }];

        expect(report.contentId).to.equal(@"abc123");
        expect(report.title).to.equal(@"JSON Test");
        expect(report.summary).to.equal(@"Test the JSON meta-data mechanism");
        expect(report.lat).to.equal(@39.8);
        expect(report.lon).to.equal(@-104.8);
        expect(report.thumbnail).to.equal(@"images/test.png");
        expect(report.tileThumbnail).to.equal(@"images/test-tile.png");
        expect(report.importStatus).to.equal(ReportImportStatusNewLocal);
        expect(report.isImportFinished).to.equal(NO);
    });

    it(@"leaves properties not in the descriptor intact", ^{
        Report *report = [[Report alloc] init];

        report.contentId = @"/path/to/report";
        report.title = @"/path/to/report";
        report.summary = @"/path/to/report";
        report.lat = nil;
        report.lon = nil;
        report.thumbnail = @"default.png";
        report.tileThumbnail = @"default_tile.png";

        [report setPropertiesFromJsonDescriptor:@{
            @"description": @"new description",
            @"tile_thumbnail": @"my_tile.png",
        }];

        expect(report.contentId).to.equal(@"/path/to/report");
        expect(report.title).to.equal(@"/path/to/report");
        expect(report.summary).to.equal(@"new description");
        expect(report.lat).to.beNil();
        expect(report.lon).to.beNil();
        expect(report.thumbnail).to.equal(@"default.png");
        expect(report.tileThumbnail).to.equal(@"my_tile.png");
        expect(report.importStatus).to.equal(ReportImportStatusNewLocal);
        expect(report.isImportFinished).to.equal(NO);
    });

    it(@"indicates import finished when status is success or failed", ^{
        Report *report = [[Report alloc] init];

        expect(report.importStatus).to.equal(ReportImportStatusNewLocal);
        expect(report.isImportFinished).to.equal(NO);

        report.importStatus = ReportImportStatusDownloading;
        expect(report.isImportFinished).to.equal(NO);

        report.importStatus = ReportImportStatusExtracting;
        expect(report.isImportFinished).to.equal(NO);

        report.importStatus = ReportImportStatusImporting;
        expect(report.isImportFinished).to.equal(NO);

        report.importStatus = ReportImportStatusFailed;
        expect(report.isImportFinished).to.equal(YES);

        report.importStatus = ReportImportStatusSuccess;
        expect(report.isImportFinished).to.equal(YES);
    });

    describe(@"NSCoding support", ^{

        it(@"encodes and decodes properly", ^{

            NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice" isDirectory:YES];
            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"NSCoding.zip" isDirectory:NO];
            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"NSCoding.zip.dice_import" isDirectory:YES];
            NSURL *baseDir = [importDir URLByAppendingPathComponent:@"NSCoding" isDirectory:YES];
            NSURL *rootFile = [baseDir URLByAppendingPathComponent:@"index.txt" isDirectory:NO];

            Report *original = [[Report alloc] init];
            original.baseDir = baseDir;
            original.contentId = @"dice.test.NSCoding";
            original.downloadProgress = 75;
            original.downloadSize = 123456;
            original.importDir = importDir;
            original.importStatus = ReportImportStatusSuccess;
            original.isEnabled = YES;
            original.lat = @36.0;
            original.lon = @(-104.0);
            original.remoteSource = [NSURL URLWithString:@"http://dice.com/NSCoding.zip"];
            original.rootFile = rootFile;
            original.sourceFile = sourceFile;
            original.statusMessage = @"Imported";
            original.summary = @"Testing NSCoding support";
            original.thumbnail = @"thumbnail.png";
            original.tileThumbnail = @"tile.png";
            original.title = @"NSCoding Test";
            original.uti = (__bridge CFStringRef)@"dice.test";

            NSDictionary *properties = @{
                @"baseDir": original.baseDir,
                @"contentId": original.contentId,
                @"downloadProgress": @(original.downloadProgress),
                @"downloadSize": @(original.downloadSize),
                @"importDir": original.importDir,
                @"importStatus": @(original.importStatus),
                @"isEnabled": @(original.isEnabled),
                @"lat": original.lat,
                @"lon": original.lon,
                @"remoteSource": original.remoteSource,
                @"rootFile": original.rootFile,
                @"sourceFile": original.sourceFile,
                @"statusMessage": original.statusMessage,
                @"summary": original.summary,
                @"thumbnail": original.thumbnail,
                @"tileThumbnail": original.tileThumbnail,
                @"title": original.title,
                @"uti": (NSString *) original.uti,
            };

            NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:original];
            Report *materialized = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
            NSDictionary *originalProperties = [original dictionaryWithValuesForKeys:properties.allKeys];
            NSDictionary *materializedProperties = [materialized dictionaryWithValuesForKeys:properties.allKeys];

            assertThat(originalProperties, hasEntriesIn(properties));
            assertThat(materializedProperties, hasEntriesIn(originalProperties));
        });
    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
