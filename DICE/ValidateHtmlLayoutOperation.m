//
//  ValidateHtmlLayoutOperation.m
//  DICE
//
//  Created by Robert St. John on 12/21/15.
//  Copyright © 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import <objective-zip/OZZipFile.h>
#import "ValidateHtmlLayoutOperation.h"
#import "Objective-Zip.h"


@implementation ValidateHtmlLayoutOperation

/*
 TODO: combine this with the logic of couldImportFromPath: to DRY
 */

- (instancetype)initWithZipFile:(OZZipFile *)zipFile
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _zipFile = zipFile;

    return self;
}

- (instancetype)initWithBaseDirectory:(NSURL *)dir fileManager:(NSFileManager *)fileManager
{
    self = [super init];
    if (!self) {
        return nil;
    }

    return self;
}

- (BOOL)hasDescriptor
{
    return _descriptorPath != nil;
}

- (void)main
{
    @autoreleasepool {
        if (self.zipFile) {
            [self validateZipFile];
        }
    }
}

- (void)validateZipFile
{
    NSString *mostShallowIndexEntry = nil;
    // index.html must be at most one directory deep
    NSUInteger indexDepth = 2;
    BOOL hasNonIndexRootEntries = NO;
    NSMutableSet *baseDirs = [NSMutableSet set];

    NSArray *entries = [self.zipFile listFileInZipInfos];

    for (OZFileInZipInfo *entry in entries) {
        NSArray *steps = entry.name.pathComponents;
        if (steps.count > 1) {
            [baseDirs addObject:steps.firstObject];
        }
        if ([@"index.html" isEqualToString:steps.lastObject]) {
            if (steps.count == 1) {
                mostShallowIndexEntry = entry.name;
                indexDepth = 0;
            }
            else if (steps.count - 1 < indexDepth) {
                mostShallowIndexEntry = entry.name;
                indexDepth = steps.count - 1;
            }
        }
        else {
            // TODO: account for multiple metadata.json entries
            if ([@"metadata.json" isEqualToString:steps.lastObject]) {
                _descriptorPath = entry.name;
            }
            if (steps.count == 1) {
                hasNonIndexRootEntries = YES;
            }
        }
    }

    if (indexDepth > 0 && (hasNonIndexRootEntries || baseDirs.count > 1)) {
        mostShallowIndexEntry = nil;
        _descriptorPath = nil;
    }

    if (mostShallowIndexEntry) {
        _indexDirPath = [mostShallowIndexEntry stringByDeletingLastPathComponent];
        _isLayoutValid = YES;
    }

    if (_descriptorPath) {
        NSString *descriptorDir = [_descriptorPath stringByDeletingLastPathComponent];
        if (![_indexDirPath isEqualToString:descriptorDir]) {
            _descriptorPath = nil;
        }
    }
}

@end
