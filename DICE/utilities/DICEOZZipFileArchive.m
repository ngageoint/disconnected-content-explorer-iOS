//
// Created by Robert St. John on 8/22/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <objective-zip/Objective-Zip.h>
#import "DICEOZZipFileArchive.h"
#import "DICEArchive.h"


@implementation DICEOZZipFileArchive {
    NSURL *_archiveUrl;
    CFStringRef _utType;
}

- (instancetype)initWithArchivePath:(NSURL *)path utType:(CFStringRef)utType
{
    self = [super initWithFileName:path.path mode:OZZipFileModeUnzip];

    _archiveUrl = path;
    _utType = utType;

    return self;
}

- (NSURL *)archiveUrl
{
    return _archiveUrl;
}

// TOOD: maybe unnecessary
- (CFStringRef)archiveUTType
{
    return _utType;
}

- (void)enumerateEntriesUsingBlock:(void (^)(id<DICEArchiveEntry>))block
{
    OZFileInZipInfo *info;
    [self goToFirstFileInZip];
    do {
        info = [self getCurrentFileInZipInfo];
        block(info);
    } while ([self goToNextFileInZip]);
}

@end