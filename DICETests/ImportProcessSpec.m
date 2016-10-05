
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
#import "KVOBlockObserver.h"
#import "NSOperation+Blockable.h"
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

    it(@"calls stepWillCancel and stepWillFinish", ^{

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
        expect(finishBlockCalled).to.equal(@YES);
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

        // must call start to make the op move to finished state
        [op1 cancel];
        [op1 start];
        [op2 cancel];
        [op2 start];

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

    it(@"is finished when all steps are finished", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [op1 start];

        expect(op1.isFinished).to.equal(YES);
        expect(op2.isFinished).to.equal(NO);
        expect(import.isFinished).to.equal(NO);

        [op2 start];

        expect(op2.isFinished).to.equal(YES);
        expect(import.isFinished).to.equal(YES);

    });

    it(@"is finished but not successful when cancelled", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [op1 start];

        expect(op1.isFinished).to.equal(YES);
        expect(op2.isFinished).to.equal(NO);
        expect(import.isFinished).to.equal(NO);

        [import cancel];
        [op2 start];

        expect(op2.isFinished).to.equal(YES);
        expect(import.isFinished).to.equal(YES);
        expect(import.wasSuccessful).to.equal(NO);
    });

    it(@"was successful when all steps finish normally", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [op1 start];

        expect(op1.isFinished).to.equal(YES);
        expect(op2.isFinished).to.equal(NO);
        expect(import.isFinished).to.equal(NO);

        [op2 start];

        expect(op2.isFinished).to.equal(YES);
        expect(import.wasSuccessful).to.equal(YES);
    });

    it(@"was not successful when a step was cancelled", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [op1 start];

        expect(op1.isFinished).to.equal(YES);
        expect(op2.isFinished).to.equal(NO);
        expect(import.isFinished).to.equal(NO);
        expect(import.wasSuccessful).to.equal(NO);

        [op2 cancel];
        [op2 start];

        expect(op2.isFinished).to.equal(YES);
        expect(import.isFinished).to.equal(YES);
        expect(import.wasSuccessful).to.equal(NO);
    });

    it(@"remains successful if cancelled after already completing successfully", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [op1 start];

        expect(op1.isFinished).to.equal(YES);
        expect(op2.isFinished).to.equal(NO);
        expect(import.isFinished).to.equal(NO);
        expect(import.wasSuccessful).to.equal(NO);

        [op2 start];

        expect(op2.isFinished).to.equal(YES);
        expect(import.wasSuccessful).to.equal(YES);

        [import cancel];

        expect(import.wasSuccessful).to.equal(YES);
    });

    it(@"notifies the delegate when the import finishes", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];
        id<ImportDelegate> delegate = mockProtocol(@protocol(ImportDelegate));
        import.delegate = delegate;

        [op1 start];
        [op2 start];

        [verify(delegate) importDidFinishForImportProcess:import];
    });

    it(@"notifies the delegate when the import fails and finishes", ^{
        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];
        id<ImportDelegate> delegate = mockProtocol(@protocol(ImportDelegate));
        import.delegate = delegate;

        [op1 start];
        [op2 cancel];
        [op2 start];

        [verify(delegate) importDidFinishForImportProcess:import];
    });

    it(@"notifies the delegate only once when a step is cancelled after starting", ^{
        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{
            NSLog(@"i'm executing!");
        }];
        ImportProcess *import = [[ImportProcess alloc] initWithReport:report];
        import.steps = @[op];
        id<ImportDelegate> delegate = mockProtocol(@protocol(ImportDelegate));
        __block NSUInteger notifiedCount = 0;
        [givenVoid([delegate importDidFinishForImportProcess:import]) willDo:^id(NSInvocation *invocation) {
            @synchronized(delegate) {
                notifiedCount++;
            }
            return nil;
        }];
        import.delegate = delegate;

        [op block];
        [ops addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        [op cancel];

        [verifyCount(delegate, never()) importDidFinishForImportProcess:import];

        [op unblock];

        assertWithTimeout(1.0, thatEventually(@(notifiedCount)), equalToUnsignedInteger(1));
        [verify(delegate) importDidFinishForImportProcess:import];
    });

    it(@"notifies the delegate only once about finishing", ^{
        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        NSOperation *op1 = [NSBlockOperation blockOperationWithBlock:^{}];
        op1.name = @"op1";
        NSOperation *op2 = [NSBlockOperation blockOperationWithBlock:^{}];
        op2.name = @"op2";
        ImportProcess *import = [[ImportProcess alloc] initWithReport:report];
        import.steps = @[op1, op2];
        id<ImportDelegate> delegate = mockProtocol(@protocol(ImportDelegate));
        __block NSUInteger notifiedCount = 0;
        [givenVoid([delegate importDidFinishForImportProcess:import]) willDo:^id(NSInvocation *invocation) {
            @synchronized(delegate) {
                notifiedCount++;
            }
            return nil;
        }];
        import.delegate = delegate;

//        [op block];
        [ops addOperations:import.steps waitUntilFinished:YES];

//        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());
//
//        [verifyCount(delegate, never()) importDidFinishForImportProcess:import];

        assertWithTimeout(1.0, thatEventually(@(notifiedCount)), greaterThanOrEqualTo(@1));
        [verify(delegate) importDidFinishForImportProcess:import];
    });

});

describe(@"NSOperation key-value observing behavior", ^{

    void *KVO_CONTEXT = &KVO_CONTEXT;

    it(@"is not finished when cancelled before executing", ^{
        __block BOOL opExecuted = NO;
        NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{opExecuted = YES;}];
        KVOBlockObserver *observer = [[[[[KVOBlockObserver alloc] initWithBlock:nil]
            observeKeyPath:@"isFinished" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld]
            observeKeyPath:@"isCancelled" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld]
            observeKeyPath:@"isExecuting" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld];

        [op cancel];

        expect(op.isFinished).to.equal(NO);
        expect(op.isCancelled).to.equal(YES);
        expect(observer.observations.count).to.equal(1);
        expect(observer.observations.firstObject.keyPath).to.equal(@"isCancelled");

        [op start];

        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(YES);
        expect(op.isExecuting).to.equal(NO);
        expect(observer.observations.count).to.equal(2);
        expect(observer.observations.lastObject.keyPath).to.equal(@"isFinished");
        expect(opExecuted).to.equal(NO);
    });

    it(@"observes isExecuting before isFinished", ^{
        __block BOOL opExecuted = NO;
        NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{opExecuted = YES;}];
        KVOBlockObserver *observer = [[[[[KVOBlockObserver alloc] initWithBlock:nil]
            observeKeyPath:@"isFinished" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld]
            observeKeyPath:@"isCancelled" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld]
            observeKeyPath:@"isExecuting" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld];

        [op start];

        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(NO);
        expect(op.isExecuting).to.equal(NO);
        expect(observer.observations.count).to.equal(3);
        expect(observer.observations[0].keyPath).to.equal(@"isExecuting");
        expect(observer.observations[1].keyPath).to.equal(@"isExecuting");
        expect(observer.observations[2].keyPath).to.equal(@"isFinished");
        expect(opExecuted).to.equal(YES);
    });

    it(@"observes isExecuting then isCancelled, then isExecuting, then isFinished", ^{
        __block BOOL opExecuted = NO;
        NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{opExecuted = YES;}];
        KVOBlockObserver *observer = [[[[[KVOBlockObserver alloc] initWithBlock:nil]
            observeKeyPath:@"isFinished" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld]
            observeKeyPath:@"isCancelled" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld]
            observeKeyPath:@"isExecuting" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld];

        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        [queue addOperation:[op block]];

        assertWithTimeout(1.0, thatEventually(@(observer.observations.count)), equalToUnsignedInteger(1));

        expect(observer.observations.count).to.equal(1);
        expect(observer.observations.lastObject.keyPath).to.equal(@"isExecuting");
        expect(observer.observations.lastObject.newValue).to.equal(@YES);
        expect(op.isExecuting).to.equal(YES);

        [op cancel];

        expect(observer.observations.lastObject.keyPath).to.equal(@"isCancelled");

        [op unblock];

        assertWithTimeout(1.0, thatEventually(observer.observations.lastObject.keyPath), equalTo(@"isFinished"));

        expect(observer.observations.count).to.equal(4);
        expect(observer.observations[2].keyPath).to.equal(@"isExecuting");
        expect(observer.observations[2].change[NSKeyValueChangeKindKey]).to.equal(NSKeyValueChangeSetting);
        expect(observer.observations[2].oldValue).to.equal(@YES);
        expect(observer.observations[2].newValue).to.equal(@NO);
        expect(observer.observations[3].keyPath).to.equal(@"isFinished");
        expect(observer.observations[3].newValue).to.equal(@YES);
        expect(op.isFinished).to.equal(YES);
        expect(op.isCancelled).to.equal(YES);
        expect(op.isExecuting).to.equal(NO);
    });

    it(@"observes expected changes for isExecuting", ^{
        __block BOOL opExecuted = NO;
        NSOperation *op = [[NSOperation alloc] init];
        KVOBlockObserver *observer = [[[[[KVOBlockObserver alloc] initWithBlock:nil]
            observeKeyPath:@"isFinished" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld]
            observeKeyPath:@"isCancelled" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld]
            observeKeyPath:@"isExecuting" ofObject:op inContext:KVO_CONTEXT options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld];

        [op start];

        expect(observer.observations.count).to.equal(3);
        expect(observer.observations[0].keyPath).to.equal(@"isExecuting");
        expect(observer.observations[0].newValue).to.equal(YES);
        expect(observer.observations[1].keyPath).to.equal(@"isExecuting");
        expect(observer.observations[1].newValue).to.equal(NO);
        expect(op.isExecuting).to.equal(NO);
        expect(observer.observations[2].keyPath).to.equal(@"isFinished");
        
    });

});

SpecEnd
