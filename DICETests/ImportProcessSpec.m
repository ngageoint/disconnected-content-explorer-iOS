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

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#import "ImportProcess+Internal.h"


@interface TestBaseImportProcess : ImportProcess

@property void (^willFinishBlock)(NSOperation *);
@property void (^willCancelBlock)(NSOperation *);

- (instancetype)initWithReport:(Report *)report steps:(NSArray *)steps;

@end

@implementation TestBaseImportProcess

- (instancetype)initWithReport:(Report *)report steps:(NSArray *)steps
{
    self = [super initWithReport:report];
    self.steps = steps;
    return self;
}

- (void)stepWillFinish:(NSOperation *)step
{
    if (self.willFinishBlock != nil) {
        self.willFinishBlock(step);
    }
}

- (void)stepWillCancel:(NSOperation *)step
{
    if (self.willCancelBlock != nil) {
        self.willCancelBlock(step);
    }
}

@end


SpecBegin(ImportProcess)

describe(@"ImportProcess", ^{

    __block Report *report;
    
    beforeAll(^{
    });
    
    beforeEach(^{
        report = [[Report alloc] initWithTitle:@"ImportProcess Test"];
    });

    afterEach(^{
    });

    afterAll(^{
    });

    it(@"calls stepWillFinish before dependent operations are ready", ^{

        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        [op2 addDependency:op1];

        __block NSOperation *finishedStep = nil;
        __block NSNumber *op2WasReady = nil;

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];
        import.willFinishBlock = ^(NSOperation *step) {
            finishedStep = step;
            op2WasReady = @(op2.ready);
        };

        [op1 start];

        [self expectationForPredicate:[NSPredicate predicateWithFormat:@"ready == YES" arguments:nil] evaluatedWithObject:op2 handler:nil];
        [self waitForExpectationsWithTimeout:1.0 handler:nil];

        expect(op1.finished).to.equal(YES);
        expect(finishedStep).to.beIdenticalTo(op1);
        expect(op2WasReady).to.equal(@NO);
    });

    it(@"calls stepWillCancel but not stepWillFinish", ^{

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];

        NSOperation *op1 = [NSBlockOperation blockOperationWithBlock:^{
            while (op1.isExecuting);
        }];

        __block NSNumber *finishBlockCalled = nil;
        __block NSNumber *cancelBlockCalled = nil;

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1]];
        import.willFinishBlock = ^(NSOperation *step) {
            finishBlockCalled = @YES;
        };
        import.willCancelBlock = ^(NSOperation *step) {
            cancelBlockCalled = @YES;
        };

        [ops addOperation:op1];
        while (!op1.isExecuting);
        [op1 cancel];

        NSPredicate *notExecuting = [NSPredicate predicateWithFormat:@"isExecuting == NO AND isCancelled == YES"];
        [self expectationForPredicate:notExecuting evaluatedWithObject:op1 handler:nil];
        [self waitForExpectationsWithTimeout:1.0 handler:nil];

        expect(cancelBlockCalled).to.equal(@YES);
        expect(finishBlockCalled).to.beNil;

        [op1 waitUntilFinished];
    });

    it(@"stops observing operations after they finish", ^{

        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [op1 start];
        [op2 start];

        NSPredicate *opsFinished = [NSPredicate predicateWithFormat:@"%@.isFinished == YES AND %@.isFinished == YES", op1, op2];
        [self expectationForPredicate:opsFinished evaluatedWithObject:self handler:nil];
        [self waitForExpectationsWithTimeout:1.0 handler:nil];

        expect(^{[op1 removeObserver:import forKeyPath:@"isFinished"];}).to.raiseAny();
        expect(^{[op1 removeObserver:import forKeyPath:@"isExecuting"];}).to.raiseAny();
        expect(^{[op1 removeObserver:import forKeyPath:@"isCancelled"];}).to.raiseAny();
        expect(^{[op2 removeObserver:import forKeyPath:@"isFinished"];}).to.raiseAny();
        expect(^{[op2 removeObserver:import forKeyPath:@"isExecuting"];}).to.raiseAny();
        expect(^{[op1 removeObserver:import forKeyPath:@"isCancelled"];}).to.raiseAny();
    });

    it(@"stops observing operations if cancelled", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [op1 cancel];
        [op2 cancel];

        NSPredicate *opsFinished = [NSPredicate predicateWithFormat:@"%@.isCancelled == YES AND %@.isCancelled == YES", op1, op2];
        [self expectationForPredicate:opsFinished evaluatedWithObject:self handler:nil];
        [self waitForExpectationsWithTimeout:1.0 handler:nil];

        expect(^{[op1 removeObserver:import forKeyPath:@"isFinished"];}).to.raiseAny();
        expect(^{[op1 removeObserver:import forKeyPath:@"isExecuting"];}).to.raiseAny();
        expect(^{[op1 removeObserver:import forKeyPath:@"isCancelled"];}).to.raiseAny();
        expect(^{[op2 removeObserver:import forKeyPath:@"isFinished"];}).to.raiseAny();
        expect(^{[op2 removeObserver:import forKeyPath:@"isExecuting"];}).to.raiseAny();
        expect(^{[op2 removeObserver:import forKeyPath:@"isCancelled"];}).to.raiseAny();
    });

    it(@"begins with the current step at -1", ^{

        NSOperation *op1 = mock([NSOperation class]);
        NSOperation *op2 = mock([NSOperation class]);

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        expect(import.currentStep).to.equal(-1);

    });

    it(@"sets the current step to 0 when the first operation starts", ^{

    });

});

SpecEnd
