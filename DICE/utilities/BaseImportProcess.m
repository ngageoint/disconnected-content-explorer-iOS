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

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSUInteger stepIndex = [self.steps indexOfObject:object];

    if (stepIndex == NSNotFound) {
        return;
    }

    BOOL isPrior = ((NSNumber *)change[NSKeyValueChangeNotificationIsPriorKey]).boolValue;
    
    if ([@"isFinished" isEqualToString:keyPath] && isPrior) {
        [self stepWillFinish:object stepIndex:stepIndex];
        // TODO: remove observer?
    }
}

- (void)stepWillFinish:(NSOperation *)step stepIndex:(NSUInteger)stepIndex
{

}

@end
