//
//  ImportProcess.m
//  DICE
//
//  Created by Robert St. John on 5/19/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ImportProcess+Internal.h"
#import "Report.h"


@implementation ImportProcess
{
    void *OBSERVATION_CONTEXT;
    NSArray<NSOperation *> *_steps;
    Report *_report;
}

- (instancetype)initWithReport:(Report *)report
{
    self = [super init];

    if (!self) {
        return nil;
    }

    OBSERVATION_CONTEXT = &OBSERVATION_CONTEXT;

    _report = report;

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

- (Report *)report
{
    @synchronized (self) {
        return _report;
    }
}

- (void)setReport:(Report *)report
{
    @synchronized (self) {
        _report = report;
    }
}

- (BOOL)isFinished
{
    @synchronized (self) {
        for (NSOperation *step in self.steps) {
            if (step.isExecuting || !(step.isFinished || step.isCancelled)) {
                return NO;
            }
        }
        return YES;
    }
}

- (BOOL)wasSuccessful
{
    @synchronized (self) {
        for (NSOperation *step in self.steps) {
            if (!step.isFinished || step.isCancelled) {
                return NO;
            }
        }
        return YES;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != OBSERVATION_CONTEXT) {
        return;
    }

    NSOperation *op = (NSOperation *)object;
    BOOL isPrior = ((NSNumber *)change[NSKeyValueChangeNotificationIsPriorKey]).boolValue;
    if (isPrior) {
        if ([keyPath isEqualToString:NSStringFromSelector(@selector(isFinished))]) {
            [self stepWillFinish:object];
        }
        else if ([keyPath isEqualToString:NSStringFromSelector(@selector(isCancelled))]) {
            [self stepWillCancel:object];
        }
    }
    else {
        if (!op.isExecuting) {
            [self stopObserving:object];
        }
        [self notifyDelegateIfFinished];
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

- (void)notifyDelegateIfFinished
{
    if (self.isFinished && self.delegate) {
        [self.delegate importDidFinishForImportProcess:self];
    }
}

- (void)observeStep:(NSOperation *)step
{
    [step addObserver:self forKeyPath:NSStringFromSelector(@selector(isExecuting)) options:NSKeyValueObservingOptionPrior context:OBSERVATION_CONTEXT];
    [step addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:NSKeyValueObservingOptionPrior context:OBSERVATION_CONTEXT];
    [step addObserver:self forKeyPath:NSStringFromSelector(@selector(isCancelled)) options:NSKeyValueObservingOptionPrior context:OBSERVATION_CONTEXT];
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
