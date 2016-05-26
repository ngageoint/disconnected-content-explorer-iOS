//
//  ImportProcess.m
//  DICE
//
//  Created by Robert St. John on 5/19/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ImportProcess+Internal.h"


@implementation ImportProcess
{
    void *OBSERVATION_CONTEXT;
    NSArray<NSOperation *> *_steps;
}

- (instancetype)initWithReport:(Report *)report
{
    self = [super init];

    if (!self) {
        return nil;
    }

    OBSERVATION_CONTEXT = &OBSERVATION_CONTEXT;

    _report = report;
    _currentStep = -1;

    return self;
}

- (instancetype)init
{
    return [self initWithReport:nil];
}

- (NSArray<NSOperation *> *)steps
{
    @synchronized (self) {
        return _steps;
    }
}

- (void)setSteps:(NSArray<NSOperation *> *)steps
{
    @synchronized (self) {
        if (_steps != nil) {
            for (NSOperation *step in _steps) {
                [self stopObserving:step];
            }
        }
        _steps = steps;
        if (_steps != nil) {
            for (NSOperation *step in _steps) {
                [self observeStep:step];
            }
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != OBSERVATION_CONTEXT) {
        return;
    }

    BOOL isPrior = ((NSNumber *)change[NSKeyValueChangeNotificationIsPriorKey]).boolValue;
    if (isPrior) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(isExecuting))]) {
            _currentStep += 1;
        }
        else if ([keyPath isEqualToString:NSStringFromSelector(@selector(isFinished))]) {
            [self stepWillFinish:object];
        }
        else if ([keyPath isEqualToString:NSStringFromSelector(@selector(isCancelled))]) {
            [self stepWillCancel:object];
        }
    }
    else if (![keyPath isEqualToString:NSStringFromSelector(@selector(isExecuting))]) {
        [self stopObserving:object];
    }
}

- (void)stepWillFinish:(NSOperation *)step
{

}

- (void)stepWillCancel:(NSOperation *)step
{
    
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
    [step addObserver:self forKeyPath:@"isExecuting" options:NSKeyValueObservingOptionPrior context:OBSERVATION_CONTEXT];
    [step addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionPrior context:OBSERVATION_CONTEXT];
    [step addObserver:self forKeyPath:@"isCancelled" options:NSKeyValueObservingOptionPrior context:OBSERVATION_CONTEXT];
}

- (void)stopObserving:(NSOperation *)step
{
    [step removeObserver:self forKeyPath:@"isExecuting" context:OBSERVATION_CONTEXT];
    [step removeObserver:self forKeyPath:@"isFinished" context:OBSERVATION_CONTEXT];
    [step removeObserver:self forKeyPath:@"isCancelled" context:OBSERVATION_CONTEXT];
}

@end