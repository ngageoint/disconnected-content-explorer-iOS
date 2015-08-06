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
        [step addObserver:self forKeyPath:@"executing" options:NSKeyValueObservingOptionPrior context:nil];
        [step addObserver:self forKeyPath:@"finished" options:NSKeyValueObservingOptionPrior context:nil];
    }

    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    BOOL isPrior = ((NSNumber *)change[NSKeyValueChangeNotificationIsPriorKey]).boolValue;
}

- (void)stepWillBeginExecuting:(NSOperation *)step
{

}

- (void)stepDidFinish:(NSOperation *)step
{
    
}

@end
