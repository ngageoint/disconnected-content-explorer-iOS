//
// Created by Robert St. John on 8/22/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <objective-zip/Objective-Zip.h>
#import "DICEOZZipFileArchive.h"
#import "OZZipFile+NSError.h"
#import "Objective-Zip+NSError.h"


@implementation DICEOZZipFileArchive {
    NSURL *_url;
    CFStringRef _uti;
    uint64_t _sizeExtracted;
    BOOL _sizeExtractedReady;
    OZZipReadStream *_currentReadStream;
}

- (instancetype)initWithArchivePath:(NSURL *)path archiveUti:(CFStringRef)uti
{
    self = [super initWithFileName:path.path mode:OZZipFileModeUnzip];

    _url = path;
    _uti = uti;
    _sizeExtracted = 0;
    _sizeExtractedReady = NO;

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

- (uint64_t)calculateArchiveSizeExtractedWithError:(NSError **)error
{
    if (!_sizeExtractedReady) {
        [self enumerateEntriesUsingBlock:^(id<DICEArchiveEntry> entry) {} error:error];
    }
    return _sizeExtracted;
}

- (void)enumerateEntriesUsingBlock:(void (^)(id<DICEArchiveEntry>))block error:(NSError **)error
{
    if (!_sizeExtractedReady) {
        _sizeExtracted = 0;
    }
    OZFileInZipInfo *info;
    [self goToFirstFileInZipWithError:error];
    do {
        info = [self getCurrentFileInZipInfoWithError:error];
        if (!_sizeExtractedReady) {
            _sizeExtracted += [info archiveEntrySizeExtracted];
        }
        block(info);
    } while ([self goToNextFileInZip]);
    _sizeExtractedReady = YES;
}

- (BOOL)openCurrentArchiveEntryWithError:(NSError **)error
{
    NSError __autoreleasing *localError;
    _currentReadStream = [self readCurrentFileInZipWithError:&localError];
    if (error) {
        *error = localError;
    }
    return localError == nil && _currentReadStream != nil;
}

- (NSUInteger)readCurrentArchiveEntryToBuffer:(NSMutableData *)buffer error:(NSError **)error
{
    NSInteger byteCount = [_currentReadStream readDataWithBuffer:buffer error:error];
    if (byteCount <= 0) {
        return 0;
    }
    return (NSUInteger)byteCount;
}

- (BOOL)closeCurrentArchiveEntryWithError:(NSError **)error
{
    if (_currentReadStream == nil) {
        return YES;
    }
    return [_currentReadStream finishedReadingWithError:error];
}

- (BOOL)closeArchiveWithError:(NSError **)error
{
    return [self closeWithError:error];
}


@end


@implementation OZFileInZipInfo (DICEArchiveEntry)

- (NSString *)archiveEntryPath
{
    return self.name;
}

- (uint64_t)archiveEntrySizeExtracted
{
    return self.length;
}

- (uint64_t)archiveEntrySizeInArchive
{
    return self.size;
}

- (NSDate *)archiveEntryDate
{
    return self.date;
}


@end
