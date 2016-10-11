//
// Created by Robert St. John on 10/11/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "ReportType.h"


@implementation ContentEnumerationInfo

- (void)addInfoForEntryPath:(NSString *)path size:(uint64_t)contentSize
{
    _totalContentSize += contentSize;
    _entryCount += 1;
    NSString *entryRoot = @"";
    NSArray *pathParts = path.pathComponents;
    if (pathParts.count > 1) {
        entryRoot = pathParts.firstObject;
    }
    else if (pathParts.count == 1) {
        if ([path hasSuffix:@"/"]) {
            entryRoot = pathParts.firstObject;
        }
        else {
            _baseDir = @"";
            entryRoot = nil;
        }
    }
    if (self.baseDir == nil) {
        _baseDir = entryRoot;
    }
    if (![self.baseDir isEqualToString:entryRoot]) {
        _baseDir = @"";
    }
}

- (BOOL)hasBaseDir
{
    return self.baseDir && self.baseDir.length;
}

@end
