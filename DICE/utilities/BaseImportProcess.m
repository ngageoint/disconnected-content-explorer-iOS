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
        [step addObserver:self forKeyPath:@"isFinished" options:0 context:nil];
    }

    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{

}

- (void)stepWillBeginExecuting:(NSOperation *)step
{

}

- (void)stepDidFinish:(NSOperation *)step
{
    
}

@end
