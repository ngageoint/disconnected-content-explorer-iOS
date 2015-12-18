//
//  BaseImportProcessSpec.m
//  DICE
//
//  Created by Robert St. John on 8/6/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#import <OCMock/OCMock.h>

#import "BaseImportProcess.h"


SpecBegin(BaseImportProcess)

describe(@"BaseImportProcess", ^{
    
    beforeAll(^{

    });
    
    beforeEach(^{

    });

    afterEach(^{

    });

    afterAll(^{
        
    });

    it(@"calls stepWillFinish before dependent operations are ready", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        [op2 addDependency:op1];

        __block BOOL op2WasReady = op2.ready;

        BaseImportProcess *import = [[BaseImportProcess alloc] initWithReport:[[Report alloc] init] steps:@[op1, op2]];
        import = OCMPartialMock(import);
        OCMStub([import stepWillFinish:op1 stepIndex:0]).andDo(^(NSInvocation *invocation) {
            [NSThread sleepForTimeInterval:0.25];
            op2WasReady = op2.ready;
        });

        [op1 start];
        
        expect(op1.finished).to.equal(YES);
        expect(op2WasReady).to.equal(NO);
        expect(op2.ready).to.equal(YES);

        [(id)import stopMocking];
    });

    it(@"does nothing for kvo notification on foreign import step", ^{
        NSOperation *op = [[NSOperation alloc] init];
        NSOperation *foreign = [[NSOperation alloc] init];
        BaseImportProcess *import = OCMPartialMock([[BaseImportProcess alloc] initWithReport:[[Report alloc] init] steps:@[op]]);

        [[[(OCMockObject *)import reject] ignoringNonObjectArgs] stepWillFinish:foreign stepIndex:0];

        [import observeValueForKeyPath:@"isFinished" ofObject:foreign
            change:@{ NSKeyValueChangeNotificationIsPriorKey : @YES }
            context:nil];

        [(id)import stopMocking];
    });

});

SpecEnd
