//
//  ImportProcess.m
//  DICE
//
//  Created by Robert St. John on 5/19/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//


#import "ImportProcess+Internal.h"
#import "Report.h"


@implementation ImportProcess
{
    void *OBSERVATION_CONTEXT;
    NSArray<NSOperation *> *_steps;
    Report *_report;
    NSUInteger _finishedStepCount;
    BOOL _isDelegateFinished;

@protected
    dispatch_queue_t _mutexQueue;
}

- (instancetype)initWithReport:(Report *)report
{
    self = [super init];

    if (!self) {
        return nil;
    }

    OBSERVATION_CONTEXT = &OBSERVATION_CONTEXT;

    _report = report;
    _steps = @[];
    _finishedStepCount = 0;
    _mutexQueue = dispatch_queue_create("dice.ImportProcess", DISPATCH_QUEUE_SERIAL);

    return self;
}

- (instancetype)init
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    return [self initWithReport:nil];
#pragma clang diagnostic pop
}

- (NSArray<NSOperation *> *)steps
{
    return _steps;
}

- (void)setSteps:(NSArray<NSOperation *> *)steps
{
    if (self.steps != nil) {
        for (NSOperation *step in self.steps) {
            [self stopObserving:step];
        }
    }
    _steps = steps;
    if (self.steps != nil) {
        for (NSOperation *step in self.steps) {
            [self observeStep:step];
        }
    }
}

- (Report *)report
{
    return _report;
}

- (void)setReport:(Report *)report
{
    _report = report;
}

- (BOOL)isFinished
{
    return self.isDelegateFinished;
}

- (BOOL)isDelegateFinished
{
    __block BOOL finished = NO;
    dispatch_sync(_mutexQueue, ^{
        finished = _isDelegateFinished;
    });
    return finished;
}

- (void)setIsDelegateFinished:(BOOL)isDelegateFinished
{
    dispatch_sync(_mutexQueue, ^{
        _isDelegateFinished = isDelegateFinished;
    });
}

- (BOOL)wasSuccessful
{
    __block BOOL success = NO;
    dispatch_sync(_mutexQueue, ^{
        if (_finishedStepCount < self.steps.count) {
            return;
        }
        for (NSOperation *step in self.steps) {
            if (step.isCancelled) {
                return;
            }
        }
        success = YES;
    });
    return success;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != OBSERVATION_CONTEXT) {
        return;
    }

    NSOperation *op = (NSOperation *)object;
    BOOL isPrior = ((NSNumber *)change[NSKeyValueChangeNotificationIsPriorKey]).boolValue;
    if (isPrior) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(isFinished))] && !op.isFinished) {
            [self stepWillFinish:object];
        }
        else if ([keyPath isEqualToString:NSStringFromSelector(@selector(isCancelled))] && !op.isCancelled) {
            [self stepWillCancel:object];
        }
    }
    else if ([keyPath isEqualToString:NSStringFromSelector(@selector(isFinished))] && op.isFinished) {
        [self stopObserving:op];
        __block BOOL notifyDelegate = NO;
        dispatch_sync(_mutexQueue, ^{
            if (_finishedStepCount >= self.steps.count) {
                @throw @"finished step count exceeded step count";
            }
            _finishedStepCount += 1;
            notifyDelegate = _finishedStepCount == self.steps.count;
        });
        if (!notifyDelegate) {
            return;
        }
        if (self.delegate) {
            [self.delegate importDidFinishForImportProcess:self];
        }
        self.isDelegateFinished = YES;
    }
}

- (void)stepWillFinish:(NSOperation *)step
{

}

- (void)stepWillCancel:(NSOperation *)step
{

}

- (void)cancel
{
    for (NSOperation *step in self.steps) {
        [step cancel];
    }
}

- (void)cancelStepsAfterStep:(NSOperation *)step
{
    NSUInteger stepIndex = [self.steps indexOfObject:step];
    while (++stepIndex < self.steps.count) {
        NSOperation *pendingStep = self.steps[stepIndex];
        [pendingStep cancel];
    }
}

- (void)observeStep:(NSOperation *)step
{
    [step addObserver:self forKeyPath:NSStringFromSelector(@selector(isExecuting)) options:(NSKeyValueObservingOptionPrior|NSKeyValueObservingOptionNew) context:OBSERVATION_CONTEXT];
    [step addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:(NSKeyValueObservingOptionPrior|NSKeyValueObservingOptionNew) context:OBSERVATION_CONTEXT];
    [step addObserver:self forKeyPath:NSStringFromSelector(@selector(isCancelled)) options:(NSKeyValueObservingOptionPrior|NSKeyValueObservingOptionNew) context:OBSERVATION_CONTEXT];
}

- (void)stopObserving:(NSOperation *)step
{
    @try {
        [step removeObserver:self forKeyPath:NSStringFromSelector(@selector(isExecuting)) context:OBSERVATION_CONTEXT];
    }
    @catch (NSException *e) {
        NSLog(@"error removing observer for key path isExecuting: %@: %@\n%@", e.name, e.reason, [e callStackSymbols]);
    }
    @try {
        [step removeObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) context:OBSERVATION_CONTEXT];
    }
    @catch (NSException *e) {
        NSLog(@"error removing observer for key path isFinished: %@: %@\n%@", e.name, e.reason, [e callStackSymbols]);
    }
    @try {
        [step removeObserver:self forKeyPath:NSStringFromSelector(@selector(isCancelled)) context:OBSERVATION_CONTEXT];
    }
    @catch (NSException *e) {
        NSLog(@"error removing observer for key path isCancelled: %@: %@\n%@", e.name, e.reason, [e callStackSymbols]);
    }
}

@end


@implementation NoopImportProcess

- (instancetype)initWithReport:(Report *)report
{
    self = [super initWithReport:report];
    self.steps = @[[[NSOperation alloc] init]];
    return self;
}

@end
