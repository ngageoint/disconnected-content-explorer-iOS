//
//  ValidateHtmlLayoutOperation.m
//  DICE
//
//  Created by Robert St. John on 12/21/15.
//  Copyright © 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "ValidateHtmlLayoutOperation.h"

#import "FileInZipInfo.h"
#import "FileTree.h"


@implementation ValidateHtmlLayoutOperation

/*
 TODO: combine this with the logic of couldHandleFile: to DRY
 */

- (instancetype)initWithZipFile:(ZipFile *)zipFile
{
    return nil;
}

- (instancetype)initWithFileListing:(NSEnumerator<id <FileListingEntry>> *)files
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _fileListing = files;

    return self;
}

- (BOOL)hasDescriptor
{
    return _descriptorPath != nil;
}

- (void)main
{
    @autoreleasepool {
        NSString *mostShallowIndexEntry = nil;
        // index.html must be at most one directory deep
        NSUInteger indexDepth = 2;
        BOOL hasNonIndexRootEntries = NO;
        NSMutableSet *baseDirs = [NSMutableSet set];

        for (id<FileListingEntry> entry in self.fileListing) {
            NSArray *steps = [entry fileListing_path].pathComponents;
            if (steps.count > 1) {
                [baseDirs addObject:steps.firstObject];
            }
            if ([@"index.html" isEqualToString:steps.lastObject]) {
                if (steps.count == 1) {
                    mostShallowIndexEntry = [entry fileListing_path];
                    indexDepth = 0;
                }
                else if (steps.count - 1 < indexDepth) {
                    mostShallowIndexEntry = [entry fileListing_path];
                    indexDepth = steps.count - 1;
                }
            }
            else {
                if ([@"metadata.json" isEqualToString:steps.lastObject]) {
                    _descriptorPath = [entry fileListing_path];
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
}

@end
