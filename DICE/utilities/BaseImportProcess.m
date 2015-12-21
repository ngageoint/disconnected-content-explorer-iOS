//
//  BaseImportProcess.m
//  DICE
//
//  Created by Robert St. John on 7/23/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "BaseImportProcess.h"

@implementation BaseImportProcess

- (instancetype)initWithReport:(Report *)report
{
    self = [super init];

    if (!self) {
        return nil;
    }

    return self;
}

- (instancetype)init
{
    return [self initWithReport:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (![@"isFinished" isEqualToString:keyPath]) {
        return;
    }

    BOOL isPrior = ((NSNumber *)change[NSKeyValueChangeNotificationIsPriorKey]).boolValue;
    if (isPrior) {
        [self stepWillFinish:object];
    }
    else {
        [object removeObserver:self forKeyPath:@"isFinished"];
    }

}

- (NSOperation *)nextStep
{
    NSOperation *step = [self createNextStep];
   [step addObserver:self forKeyPath:@"isFinished" options:NSKeyValueObservingOptionPrior context:nil];
    return step;
}

- (NSOperation *)createNextStep
{
    return nil;
}

- (void)stepWillFinish:(NSOperation *)step
{
    
}

@end
