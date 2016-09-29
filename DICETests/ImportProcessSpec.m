
//
//  BaseImportProcessSpec.m
//  DICE
//
//  Created by Robert St. John on 8/6/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ImportProcess+Internal.h"
#import "Report.h"


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

        assertWithTimeout(1.0, thatEventually(@(op2.isReady)), isTrue());

        expect(op1.finished).to.equal(YES);
        expect(finishedStep).to.beIdenticalTo(op1);
        expect(op2WasReady).to.equal(@NO);
    });

    it(@"calls stepWillCancel but not stepWillFinish", ^{

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{
            failure(@"cancelled operation should not run");
        }];

        __block __strong NSNumber *finishBlockCalled = nil;
        __block __strong NSNumber *cancelBlockCalled = nil;

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op]];
        import.willFinishBlock = ^(NSOperation *step) {
            finishBlockCalled = @YES;
        };
        import.willCancelBlock = ^(NSOperation *step) {
            cancelBlockCalled = @YES;
        };

        [op cancel];
        [ops addOperation:op];

        [ops waitUntilAllOperationsAreFinished];

        expect(cancelBlockCalled).to.equal(@YES);
        expect(finishBlockCalled).to.beNil();
        expect(op.isCancelled).to.equal(YES);
        expect(op.isFinished).to.equal(YES);
    });

    it(@"stops observing operations after they finish", ^{

        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [op1 start];
        [op2 start];

        assertWithTimeout(1.0, thatEventually(@(op1.isFinished && op2.isFinished)), isTrue());

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

        assertWithTimeout(1.0, thatEventually(@(op1.isCancelled && op2.isCancelled)), isTrue());

        expect(^{[op1 removeObserver:import forKeyPath:@"isFinished"];}).to.raiseAny();
        expect(^{[op1 removeObserver:import forKeyPath:@"isExecuting"];}).to.raiseAny();
        expect(^{[op1 removeObserver:import forKeyPath:@"isCancelled"];}).to.raiseAny();
        expect(^{[op2 removeObserver:import forKeyPath:@"isFinished"];}).to.raiseAny();
        expect(^{[op2 removeObserver:import forKeyPath:@"isExecuting"];}).to.raiseAny();
        expect(^{[op2 removeObserver:import forKeyPath:@"isCancelled"];}).to.raiseAny();
    });

    it(@"cancels all the operations", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];
        [import cancel];
        
        expect(op1.isCancelled).to.equal(YES);
        expect(op2.isCancelled).to.equal(YES);
    });

});

SpecEnd
