//
//  ReportSpec.m
//  DICE
//
//  Created by Robert St. John on 8/11/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
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
            @"reportID": @"abc123",
            @"title": @"JSON Test",
            @"description": @"Test the JSON meta-data mechanism",
            @"lat": @39.8,
            @"lon": @-104.8,
            @"thumbnail": @"images/test.png",
            @"tile_thumbnail": @"images/test-tile.png",
        }];

        expect(report.reportID).to.equal(@"abc123");
        expect(report.title).to.equal(@"JSON Test");
        expect(report.summary).to.equal(@"Test the JSON meta-data mechanism");
        expect(report.lat).to.equal(@39.8);
        expect(report.lon).to.equal(@-104.8);
        expect(report.thumbnail).to.equal(@"images/test.png");
        expect(report.tileThumbnail).to.equal(@"images/test-tile.png");
    });

    it(@"leaves properties not in the descriptor intact", ^{
        Report *report = [[Report alloc] init];

        report.reportID = @"/path/to/report";
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

        expect(report.reportID).to.equal(@"/path/to/report");
        expect(report.title).to.equal(@"/path/to/report");
        expect(report.summary).to.equal(@"new description");
        expect(report.lat).to.beNil;
        expect(report.lon).to.beNil;
        expect(report.thumbnail).to.equal(@"default.png");
        expect(report.tileThumbnail).to.equal(@"my_tile.png");
    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
