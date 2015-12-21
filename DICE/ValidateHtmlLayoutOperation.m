//
//  ValidateHtmlLayoutOperation.m
//  DICE
//
//  Created by Robert St. John on 12/21/15.
//  Copyright © 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "ValidateHtmlLayoutOperation.h"

#import "FileInZipInfo.h"



@implementation ValidateHtmlLayoutOperation

/*
 TODO: combine this with the logic of couldHandleFile: to DRY
 */

- (instancetype)initWithZipFile:(ZipFile *)zipFile
{
    self = [super init];

    if (!self) {
        return nil;
    }

    _zipFile = zipFile;

    return self;
}

- (BOOL)hasDescriptor
{
    return _descriptorPath != nil;
}

- (void)main
{
    @autoreleasepool {
        NSArray *entries = [self.zipFile listFileInZipInfos];

        __block NSString *mostShallowIndexEntry = nil;
        // index.html must be at most one directory deep
        __block NSUInteger indexDepth = 2;
        __block BOOL hasNonIndexRootEntries = NO;
        NSMutableSet *baseDirs = [NSMutableSet set];

        [entries enumerateObjectsUsingBlock:^(FileInZipInfo *entry, NSUInteger index, BOOL *stop) {
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
                if ([@"metadata.json" isEqualToString:steps.lastObject]) {
                    _descriptorPath = entry.name;
                }
                if (steps.count == 1) {
                    hasNonIndexRootEntries = YES;
                }
            }
        }];

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
}

@end
