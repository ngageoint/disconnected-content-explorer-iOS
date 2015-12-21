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

#import "BaseImportProcess.h"


@interface TestBaseImportProcess : BaseImportProcess

@property NSArray *steps;
@property NSInteger stepCursor;
@property NSMutableArray<NSOperation *> *finishedSteps;
@property (strong) void (^willFinishBlock)(NSOperation *);

- (instancetype)initWithReport:(Report *)report steps:(NSArray *)steps;

@end

@implementation TestBaseImportProcess

- (instancetype)initWithReport:(Report *)report steps:(NSArray *)steps
{
    self = [super initWithReport:report];
    _steps = steps;
    _stepCursor = 0;
    _finishedSteps = [NSMutableArray array];
    return self;
}

- (NSOperation *)nextStep
{
    if (self.stepCursor < 0) {
        return nil;
    }
    if (self.steps) {
        if (self.stepCursor >= self.steps.count) {
            return nil;
        }
        return self.steps[self.stepCursor++];
    }
    NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{}];
    op.name = [NSString stringWithFormat:@"TestBaseImportProcess-%ld", 1 + self.stepCursor++];
    return op;
}

- (void)stepWillFinish:(NSOperation *)step
{
    [self.finishedSteps addObject:step];
    if (self.willFinishBlock) {
        self.willFinishBlock(step);
    }
}

- (void)noMoreSteps
{
    self.stepCursor = -1;
}

@end


SpecBegin(BaseImportProcess)

describe(@"BaseImportProcess", ^{

    __block Report *report;
    
    beforeAll(^{
    });
    
    beforeEach(^{
        report = [[Report alloc] initWithTitle:@"BaseImportProcess Test"];
    });

    afterEach(^{
    });

    afterAll(^{
    });

    it(@"delegates step creation to the subclass", ^{

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report];
        NSOperation *step = [import nextStep];

        expect(step.name).to.equal(@"TestBaseImportProcess-1");
    });

    it(@"calls stepWillFinish before dependent operations are ready", ^{

        NSOperation *op1 = [[NSOperation alloc] init];
        NSOperation *op2 = [[NSOperation alloc] init];

        [op2 addDependency:op1];

        __block NSOperation *finishedStep;
        __block BOOL op2WasReady = op2.ready;

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];
        import.willFinishBlock = ^(NSOperation *step) {
            finishedStep = step;
            op2WasReady = op2.ready;
        };

        [op1 start];
        
        expect(op1.finished).to.equal(YES);
        expect(op2WasReady).to.equal(NO);
        expect(op2.ready).to.equal(YES);
    });

    it(@"stops observing operations after they finish", ^{

        NSOperation *op1 = mock([NSOperation class]);
        NSOperation *op2 = mock([NSOperation class]);

        TestBaseImportProcess *import = [[TestBaseImportProcess alloc] initWithReport:report steps:@[op1, op2]];

        [import observeValueForKeyPath:@"isFinished" ofObject:op1 change:@{ NSKeyValueChangeNotificationIsPriorKey: @YES } context:nil];

        [verifyCount(op1, times(0)) removeObserver:import forKeyPath:@"isFinished"];

        [import observeValueForKeyPath:@"isFinished" ofObject:op1
            change:@{ NSKeyValueChangeNotificationIsPriorKey: @NO }
            context:nil];

        [import observeValueForKeyPath:@"isFinished" ofObject:op2
            change:@{} context:nil];

        [verifyCount(op1, times(1)) removeObserver:import forKeyPath:@"isFinished"];
        [verifyCount(op2, times(1)) removeObserver:import forKeyPath:@"isFinished"];
    });

});

SpecEnd
