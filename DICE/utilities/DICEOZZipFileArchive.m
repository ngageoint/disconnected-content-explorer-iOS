//
// Created by Robert St. John on 8/22/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <objective-zip/Objective-Zip.h>
#import "DICEOZZipFileArchive.h"


@implementation DICEOZZipFileArchive {
    NSURL *_url;
    CFStringRef _uti;
}

- (instancetype)initWithArchivePath:(NSURL *)path archiveUti:(CFStringRef)uti
{
    self = [super initWithFileName:path.path mode:OZZipFileModeUnzip];

    _url = path;
    _uti = uti;

    return self;
}

- (NSURL *)archiveUrl
{
    return _url;
}

// TOOD: maybe unnecessary
- (CFStringRef)archiveUTType
{
    return _uti;
}

- (void)enumerateEntriesUsingBlock:(BOOL (^)(id<DICEArchiveEntry>))block
{
    OZFileInZipInfo *info;
    [self goToFirstFileInZip];
    do {
        info = [self getCurrentFileInZipInfo];
        if (!block(info)) {
            return;
        }
    } while ([self goToNextFileInZip]);
}

@end


@implementation OZFileInZipInfo (DICEArchiveEntry)

- (NSString *)archiveEntryPath
{
    return self.name;
}

- (archive_size_t)archiveEntrySizeExtracted
{
    return self.length;
}

- (archive_size_t)archiveEntrySizeInArchive
{
    return self.size;
}

@end