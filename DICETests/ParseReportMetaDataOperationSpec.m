//
//  ParseReportMetaDataOperationSpec.m
//  DICE
//
//  Created by Robert St. John on 8/5/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#import <OCMock/OCMock.h>

#import "ParseReportMetaDataOperation.h"


SpecBegin(ParseReportMetaDataOperation)

describe(@"ParseReportMetaDataOperation", ^{
    
    beforeAll(^{

    });
    
    beforeEach(^{

    });

    it(@"it throws an exception if report is nil", ^{
        __block ParseReportMetaDataOperation *op;

        expect(^{
            op = [[ParseReportMetaDataOperation alloc] initWithTargetReport:nil];
        }).to.raiseWithReason(@"IllegalArgumentException", @"targetReport is nil");

        expect(op).to.beNil;
    });

    it(@"is not ready until json url is set", ^{
        ParseReportMetaDataOperation *op = [[ParseReportMetaDataOperation alloc] initWithTargetReport:[[Report alloc] init]];

        id observer = observer = OCMClassMock([NSObject class]);
        OCMExpect([observer observeValueForKeyPath:@"ready" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);

        [op addObserver:observer forKeyPath:@"ready" options:0 context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.jsonFileUrl).to.beNil;

        op.jsonFileUrl = [NSURL URLWithString:@"/metadata.json"];

        expect(op.ready).to.equal(YES);
        OCMVerifyAll(observer);
    });

    it(@"is not ready until dependencies are finished", ^{
        ParseReportMetaDataOperation *op = [[ParseReportMetaDataOperation alloc] initWithTargetReport:[[Report alloc] init]];
        op.jsonFileUrl = [NSURL URLWithString:@"/metadata.json"];

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
        ParseReportMetaDataOperation *op = [[ParseReportMetaDataOperation alloc] initWithTargetReport:[[Report alloc] init]];
        op.jsonFileUrl = [NSURL URLWithString:@"/metadata.json"];

        ParseReportMetaDataOperation *mockOp = OCMPartialMock(op);
        OCMStub([mockOp isExecuting]).andReturn(YES);

        expect(^{
            op.jsonFileUrl = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.jsonFileUrl.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change jsonFileUrl after ParseReportMetaDataOperation has started");
        
        expect(op.jsonFileUrl).to.equal([NSURL URLWithString:@"/metadata.json"]);
    });

    it(@"parses the meta-data and updates the report", ^{
        failure(@"unimplemented");
    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
