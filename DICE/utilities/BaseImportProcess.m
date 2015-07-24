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

    _steps = [NSMutableArray array];

    return self;
}

- (NSOperation *)nextStep
{
    NSOperation *next = self.steps.firstObject;
    if (self.steps.count > 0) {
        [self.steps removeObjectAtIndex:0];
    }
    return next;
}

- (BOOL)hasNextStep
{
    return self.steps.count > 0;
}

@end
