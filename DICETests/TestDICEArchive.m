//
// Created by Robert St. John on 9/12/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import "TestDICEArchive.h"


#define _TDA_CHECK_ERROR_RETURNING_BOOL_ if (self.errorQueue.firstObject) { \
    if (error) { \
        *error = [self dequeuError]; \
    } \
    return NO; \
} \
return YES

@implementation TestDICEArchive {
    NSURL *_url;
    CFStringRef _uti;
    NSArray *_entries;
    uint64_t _sizeExtracted;
    id<DICEArchiveEntry> _currentEntry;
    uint64_t _currentEntryPos;
}

+ (instancetype)archiveWithEntries:(NSArray<id<DICEArchiveEntry>> *)entries archiveUrl:(NSURL *)url archiveUti:(CFStringRef)uti
{
    return [[self alloc] initWithEntries:entries archiveUrl:url archiveUti:uti];
}

- (void)enqueueError:(NSError *)error
{
    [self.errorQueue addObject:error];
}

- (NSError *)dequeuError
{
    NSError *err = self.errorQueue.firstObject;
    if (err) {
        [self.errorQueue removeObjectAtIndex:0];
    }
    return err;
}


- (instancetype)initWithEntries:(NSArray *)entries archiveUrl:(NSURL *)url archiveUti:(CFStringRef)uti
{
    self = [super init];

    _url = url;
    _uti = uti;
    _entries = entries;
    _sizeExtracted = 0;
    _errorQueue = [NSMutableArray array];
    _currentEntryPos = 0;

    return self;
}

- (NSURL *)archiveUrl
{
    return _url;
}

- (CFStringRef)archiveUTType
{
    return _uti;
}

- (uint64_t)calculateArchiveSizeExtractedWithError:(NSError **)error
{
    if (self.errorQueue.firstObject) {
        if (error) {
            *error = [self dequeuError];
        }
        return 0;
    }
    if (!_sizeExtracted) {
        for (id<DICEArchiveEntry> e in _entries) {
            _sizeExtracted += e.archiveEntrySizeExtracted;
        }
    }
    return _sizeExtracted;
}

- (BOOL)openCurrentArchiveEntryWithError:(NSError **)error
{
    _TDA_CHECK_ERROR_RETURNING_BOOL_;
}

- (NSUInteger)readCurrentArchiveEntryToBuffer:(NSMutableData *)buffer error:(NSError **)error
{
    if (!_currentEntry) {
        if (error) {
            *error = [NSError errorWithDomain:@"TestDICEArchive" code:0 userInfo:@{
                NSLocalizedFailureReasonErrorKey: @"no current archive entry"
            }];
        }
        return 0;
    }
    if (self.errorQueue.firstObject) {
        if (error) {
            *error = [self dequeuError];
        }
        return 0;
    }

    uint64_t entrySize = _currentEntry.archiveEntrySizeExtracted;
    if (entrySize <= _currentEntryPos) {
        return 0;
    }

    NSUInteger bufferSize = buffer.length;
    NSUInteger bytesRemaining = (NSUInteger)(entrySize - _currentEntryPos);
    NSUInteger readCount = MIN(bufferSize, bytesRemaining);

    const char *bytes = "abcdefghijklmnopqrstuvwxyz";
    bytesRemaining = readCount;
    while (bytesRemaining > 0) {
        NSUInteger writeCount = MIN(bytesRemaining, 26);
        [buffer replaceBytesInRange:NSMakeRange(readCount - bytesRemaining, writeCount) withBytes:bytes length:writeCount];
        bytesRemaining -= writeCount;
    }

    _currentEntryPos += readCount;

    return readCount;
}

- (BOOL)closeCurrentArchiveEntryWithError:(NSError **)error
{
    _TDA_CHECK_ERROR_RETURNING_BOOL_;
}

- (BOOL)closeArchiveWithError:(NSError **)error
{
    _TDA_CHECK_ERROR_RETURNING_BOOL_;
}


- (void)enumerateEntriesUsingBlock:(void (^)(id<DICEArchiveEntry>))block error:(NSError **)error
{
    for (id<DICEArchiveEntry> entry in _entries) {
        _currentEntry = entry;
        _currentEntryPos = 0;
        block(entry);
    }
}

@end


@implementation TestDICEArchiveEntry {
    NSString *_name;
    uint64_t _sizeInArchive;
    uint64_t _sizeExtracted;
}

+ (instancetype)entryWithName:(NSString *)name sizeInArchive:(uint64_t)inArchive sizeExtracted:(uint64_t)extracted
{
    return [[self alloc] initWithName:name sizeInArchive:inArchive sizeExtracted:extracted];
}

- (instancetype)initWithName:(NSString *)name sizeInArchive:(uint64_t)inArchive sizeExtracted:(uint64_t)extracted
{
    self = [super init];

    _name = name;
    _sizeInArchive = inArchive;
    _sizeExtracted = extracted;

    return self;
}

- (NSString *)archiveEntryPath
{
    return _name;
}

- (uint64_t)archiveEntrySizeExtracted
{
    return _sizeExtracted;
}

- (uint64_t)archiveEntrySizeInArchive
{
    return _sizeInArchive;
}

- (NSDate *)archiveEntryDate
{
    return [NSDate date];
}


@end
