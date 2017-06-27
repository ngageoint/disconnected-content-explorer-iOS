//
//  NSFileManager+Convenience.m
//  DICE
//
//  Created by Robert St. John on 6/26/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "NSFileManager+Convenience.h"

@implementation NSFileManager (Convenience)

- (BOOL)isDirectoryAtUrl:(NSURL *)url
{
    BOOL isDir;
    return [self fileExistsAtPath:url.path isDirectory:&isDir] && isDir;
}

- (BOOL)isRegularFileAtUrl:(NSURL *)url
{
    BOOL isDir;
    return [self fileExistsAtPath:url.path isDirectory:&isDir] && !isDir;
}

@end
