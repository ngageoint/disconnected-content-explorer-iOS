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

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#import "ParseJsonOperation.h"


@interface BlockedParseJsonOperation : ParseJsonOperation
@end

@implementation BlockedParseJsonOperation
{
    BOOL _blocked;
    NSCondition *_blockLock;
}

- (instancetype)init {
    self = [super init];

    _blocked = NO;
    _blockLock = [[NSCondition alloc] init];

    return self;
}

- (void)block {
    [_blockLock lock];
    _blocked = YES;
    [_blockLock unlock];
}

- (void)unblock {
    [_blockLock lock];
    _blocked = NO;
    [_blockLock signal];
    [_blockLock unlock];
}

- (void)main {
    [_blockLock lock];
    while (_blocked) {
        [_blockLock wait];
    }
    [_blockLock unlock];
}

@end


SpecBegin(ParseJsonOperation)

describe(@"ParseJsonOperation", ^{
    
    beforeAll(^{

    });
    
    beforeEach(^{

    });

    it(@"is not ready until json url is set", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];

        id observer = mock([NSObject class]);

        [op addObserver:observer forKeyPath:@"isReady" options:NSKeyValueObservingOptionPrior context:NULL];
        [op addObserver:observer forKeyPath:@"jsonUrl" options:NSKeyValueObservingOptionPrior context:NULL];

        expect(op.isReady).to.equal(NO);
        expect(op.jsonUrl).to.beNil;

        op.jsonUrl = [NSURL URLWithString:@"/metadata.json"];

        expect(op.isReady).to.equal(YES);

        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL];
        [verify(observer) observeValueForKeyPath:@"jsonUrl" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL];
        [verify(observer) observeValueForKeyPath:@"jsonUrl" ofObject:op change:isNot(hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES)) context:NULL];
        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:isNot(hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES)) context:NULL];

        [op removeObserver:observer forKeyPath:@"isReady"];
        [op removeObserver:observer forKeyPath:@"jsonUrl"];
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
        [self waitForExpectationsWithTimeout:1.0 handler:^(NSError * _Nullable error) {
            expect(op.ready).to.equal(YES);
        }];
    });

    it(@"throws an exception when json url change is attempted while executing", ^{
        BlockedParseJsonOperation *op = [[BlockedParseJsonOperation alloc] init];
        op.jsonUrl = [NSURL URLWithString:@"/metadata.json"];

        [op block];

        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        [queue addOperation:op];

        [self expectationForPredicate:[NSPredicate predicateWithFormat:@"isExecuting == YES"] evaluatedWithObject:op handler:nil];
        [self waitForExpectationsWithTimeout:1.0 handler:nil];

        expect(^{
            op.jsonUrl = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.jsonUrl.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change jsonFileUrl after ParseReportMetaDataOperation has started");

        [op unblock];

        [self expectationForPredicate:[NSPredicate predicateWithFormat:@"isFinished == YES"] evaluatedWithObject:op handler:nil];
        [self waitForExpectationsWithTimeout:1.0 handler:nil];

        expect(op.jsonUrl).to.equal([NSURL URLWithString:@"/metadata.json"]);
    });

    it(@"parses the json", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];

        NSBundle *bundle = [NSBundle bundleForClass:[ParseJsonOperationSpec class]];
        NSURL *jsonUrl = [NSURL fileURLWithPath:[bundle pathForResource:@"ParseJsonOperationSpec" ofType:@"json"]];
        op.jsonUrl = jsonUrl;

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
