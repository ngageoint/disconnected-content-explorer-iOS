//
//  MoveFileOperation.m
//  DICE
//
//  Created by Robert St. John on 7/28/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "MoveFileOperation.h"

@implementation MoveFileOperation

- (void)main
{
    @autoreleasepool {
        
    }
}

- (instancetype)initWithSourcePath:(NSURL *)source destPath:(NSURL *)destPath
{
    self = [super init];
    if (!self) {
        return nil;
    }

    return self;
}

- (instancetype)initWithSourcePath:(NSURL *)source destDir:(NSURL *)destDir
{
    NSURL *destPath = [destDir URLByAppendingPathComponent:source.lastPathComponent];

    return [self initWithSourcePath:source destPath:destPath];
}

@end
