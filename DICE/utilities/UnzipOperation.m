//
//  UnzipOperation.m
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "UnzipOperation.h"

@implementation UnzipOperation


+ (UnzipOperation *)unzipFile:(NSURL *)zipFile toDir:(NSURL *)destDir onQueue:(NSOperationQueue *)queue
{
    UnzipOperation *unzip = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:destDir];
    [queue addOperation:unzip];
    return unzip;
}

- (instancetype)initWithZipFile:(NSURL *)zipFile destDir:(NSURL *)destDir
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _zipFile = zipFile;
    _destDir = destDir;

    return self;
}


@end
