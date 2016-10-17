//
//  ParseReportMetaDataOperationSpec.m
//  DICE
//
//  Created by Robert St. John on 8/5/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ParseJsonOperation.h"
#import "NSOperation+Blockable.h"
#import "KVOBlockObserver.h"


SpecBegin(ParseJsonOperation)

describe(@"ParseJsonOperation", ^{

    NSBundle *bundle = [NSBundle bundleForClass:[ParseJsonOperationSpec class]];
    NSURL *jsonUrl = [NSURL fileURLWithPath:[bundle pathForResource:@"ParseJsonOperationSpec" ofType:@"json"]];

    __block NSFileManager *fileManager;

    beforeAll(^{

    });
    
    beforeEach(^{
        fileManager = mock([NSFileManager class]);
    });

    it(@"is not ready until json url is set", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] initWithFileManager:fileManager];

        id observer = mock([NSObject class]);

        [op addObserver:observer forKeyPath:@"isReady" options:NSKeyValueObservingOptionPrior context:NULL];
        [op addObserver:observer forKeyPath:@"jsonUrl" options:NSKeyValueObservingOptionPrior context:NULL];

        expect(op.isReady).to.equal(NO);
        expect(op.jsonUrl).to.beNil();

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

        assertWithTimeout(1.0, thatEventually(@(op.isReady)), isTrue());
    });

    it(@"throws an exception when json url change is attempted while executing", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];
        op.jsonUrl = jsonUrl;

        [op block];

        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        [queue addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        expect(^{
            op.jsonUrl = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.jsonUrl.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change jsonFileUrl after ParseReportMetaDataOperation has started");

        [op unblock];

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());

        expect(op.jsonUrl).to.equal(jsonUrl);
    });

    it(@"is ready if cancelled before executing", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];
        id observer = mock([NSObject class]);
        [op addObserver:observer forKeyPath:@"isReady" options:0 context:NULL];

        expect(op.isReady).to.equal(NO);

        [op cancel];

        expect(op.isReady).to.equal(YES);
        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:anything() context:NULL];
    });

    it(@"parses the json", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] initWithFileManager:[NSFileManager defaultManager]];

        op.jsonUrl = jsonUrl;

        [op start];

        NSDictionary *result = op.parsedJsonDictionary;
        expect(result[@"didItWork"]).to.equal(@YES);
        expect(result[@"number"]).to.equal(@28);
        expect(result[@"array"]).to.equal(@[@1, @2, @3]);
        expect(result[@"string"]).to.equal(@"ner ner");
        expect(result[@"object"]).to.equal(@{@"key": @"value"});
    });

    it(@"uses the default file manager when none is given", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] init];
        expect(op.fileManager).to.beIdenticalTo([NSFileManager defaultManager]);
    });

    it(@"uses the given file manager to load the json", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] initWithFileManager:fileManager];
        op.jsonUrl = jsonUrl;
        [given([fileManager contentsAtPath:jsonUrl.path]) willReturn:[@"{}" dataUsingEncoding:NSUTF8StringEncoding]];
        [op start];
        [verify(fileManager) contentsAtPath:jsonUrl.path];
    });

    it(@"sets the parsed dictionary to nil if file manager cannot load the url", ^{
        ParseJsonOperation *op = [[ParseJsonOperation alloc] initWithFileManager:[NSFileManager defaultManager]];
        op.jsonUrl = [NSURL fileURLWithPath:@"/path/to/nowhere.json" isDirectory:NO];
        [op start];
        expect(op.parsedJsonDictionary).to.beNil();
    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
