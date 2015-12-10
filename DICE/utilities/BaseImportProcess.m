//
//  BaseImportProcess.m
//  DICE
//
//  Created by Robert St. John on 7/23/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "BaseImportProcess.h"

@implementation BaseImportProcess

- (instancetype)initWithReport:(Report *)report steps:(NSArray *)steps
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _report = report;
    _steps = steps;

    for (NSOperation *step in _steps) {
        [step addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionPrior context:nil];
    }

    return self;
}

- (instancetype)init
{
    return [self initWithReport:nil steps:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (![@"isFinished" isEqualToString:keyPath]) {
        return;
    }

    NSUInteger stepIndex = [self.steps indexOfObjectIdenticalTo:object];

    if (stepIndex == NSNotFound) {
        return;
    }

    BOOL isPrior = ((NSNumber *)change[NSKeyValueChangeNotificationIsPriorKey]).boolValue;
    if (isPrior) {
        [self stepWillFinish:object stepIndex:stepIndex];
    }
    else {
        NSUInteger pos = [self.steps indexOfObjectPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return !([(NSOperation *)obj isFinished] || [(NSOperation *)obj isCancelled]);
        }];
        if (pos == NSNotFound) {
            [self.delegate importDidFinishForImportProcess:self];
        }
    }

}

- (void)stepWillFinish:(NSOperation *)step stepIndex:(NSUInteger)stepIndex
{

}

@end
