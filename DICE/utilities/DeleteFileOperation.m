//
//  DeleteFileOperation.m
//  DICE
//
//  Created by Robert St. John on 7/23/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "DeleteFileOperation.h"

@implementation DeleteFileOperation


- (instancetype)initWithFile:(NSURL *)file
{
    self = [super init];

    if (!self) {
        return nil;
    }

    _file = file;

    return self;
}

- (void)main
{
    @autoreleasepool {
        
    }
}

@end
