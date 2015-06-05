//
//  UnzipOperation.m
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "UnzipOperation.h"

#import "SimpleFileManager.h"

@implementation UnzipOperation

- (instancetype)initWithZipFile:(NSURL *)zipFile destDir:(NSURL *)destDir fileManager:(id<SimpleFileManager>)fileManager
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _zipFile = zipFile;
    _destDir = destDir;

    return self;
}

- (void)main
{

}


@end
