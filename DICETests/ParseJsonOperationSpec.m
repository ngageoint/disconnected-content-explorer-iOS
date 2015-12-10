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

#import "ParseJsonOperation.h"


SpecBegin(ParseJsonOperation)

describe(@"ParseJsonOperation", ^{
    
    beforeAll(^{

    });
    
    beforeEach(^{

    });

    it(@"is not ready until json url is set", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];

        id observer = observer = OCMStrictClassMock([NSObject class]);
        [observer setExpectationOrderMatters:YES];

        OCMExpect([observer observeValueForKeyPath:@"isReady" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"jsonUrl" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"jsonUrl" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);
        OCMExpect([observer observeValueForKeyPath:@"isReady" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);

        [op addObserver:observer forKeyPath:@"isReady" options:NSKeyValueObservingOptionPrior context:NULL];
        [op addObserver:observer forKeyPath:@"jsonUrl" options:NSKeyValueObservingOptionPrior context:NULL];

        expect(op.isReady).to.equal(NO);
        expect(op.jsonUrl).to.beNil;

        op.jsonUrl = [NSURL URLWithString:@"/metadata.json"];

        expect(op.isReady).to.equal(YES);
        OCMVerifyAll(observer);
    });

    it(@"is not ready until dependencies are finished", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];
        op.jsonUrl = [NSURL URLWithString:@"/metadata.json"];

        NSOperation *holdup = [[NSOperation alloc] init];
        [op addDependency:holdup];

        expect(op.ready).to.equal(NO);

        [holdup start];

        NSPredicate *isFinished = [NSPredicate predicateWithFormat:@"finished = YES"];
        [self expectationForPredicate:isFinished evaluatedWithObject:holdup handler:nil];
        [self waitForExpectationsWithTimeout:5.0 handler:^(NSError * _Nullable error) {
            expect(op.ready).to.equal(YES);
        }];
    });

    it(@"throws an exception when dest dir change is attempted while executing", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];
        op.jsonUrl = [NSURL URLWithString:@"/metadata.json"];

        ParseJsonOperation *mockOp = OCMPartialMock(op);
        OCMStub([mockOp isExecuting]).andReturn(YES);

        expect(^{
            op.jsonUrl = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.jsonUrl.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change jsonFileUrl after ParseReportMetaDataOperation has started");
        
        expect(op.jsonUrl).to.equal([NSURL URLWithString:@"/metadata.json"]);
    });

    it(@"parses the json", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];
        op.jsonUrl = [NSURL URLWithString:@"/tmp/metadata.json"];

        NSString *jsonString = @"{\"didItWork\": true, \"number\": 28, \"array\": [1, 2, 3], \"string\": \"ner ner\", \"object\": { \"key\": \"value\" } }";
        id mockDataClass = OCMClassMock([NSData class]);
        OCMExpect([mockDataClass dataWithContentsOfURL:op.jsonUrl]).andReturn([jsonString dataUsingEncoding:NSUTF8StringEncoding]);

        [op start];

        NSDictionary *result = op.parsedJsonDictionary;
        expect(result[@"didItWork"]).to.equal(@YES);
        expect(result[@"number"]).to.equal(@28);
        expect(result[@"array"]).to.equal(@[@1, @2, @3]);
        expect(result[@"string"]).to.equal(@"ner ner");
        expect(result[@"object"]).to.equal(@{@"key": @"value"});
    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
