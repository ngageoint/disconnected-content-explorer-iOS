//
//  BaseImportProcess.m
//  DICE
//
//  Created by Robert St. John on 7/23/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "BaseImportProcess.h"

@implementation BaseImportProcess
{
    NSInteger _stepCursor;
}

- (instancetype)initWithReport:(Report *)report steps:(NSArray *)steps
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _steps = steps;
    _stepCursor = 0;

    return self;
}

- (void)dealloc
{
    _steps = nil;
}

@end
