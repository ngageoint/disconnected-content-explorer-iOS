//
//  NSObject+FileOperations_m.m
//  DICE
//
//  Created by Robert St. John on 8/3/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "FileOperations.h"

@implementation MoveFileOperation

- (void)main
{
    @autoreleasepool {

    }
}

- (instancetype)initWithSourceUrl:(NSURL *)source destUrl:(NSURL *)destUrl
{
    self = [super init];
    if (!self) {
        return nil;
    }

    return self;
}

- (instancetype)initWithSourceUrl:(NSURL *)source destDirUrl:(NSURL *)destDir
{
    NSURL *dest = [destDir URLByAppendingPathComponent:source.lastPathComponent];

    return [self initWithSourceUrl:source destUrl:dest];
}

@end


@implementation DeleteFileOperation

- (instancetype)initWithFileUrl:(NSURL *)fileUrl
{
    self = [super init];

    if (!self) {
        return nil;
    }

    _fileUrl = fileUrl;

    return self;
}

- (void)main
{
    @autoreleasepool {

    }
}

@end
