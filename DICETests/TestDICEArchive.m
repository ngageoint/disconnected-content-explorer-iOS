//
// Created by Robert St. John on 9/12/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import "TestDICEArchive.h"


@implementation TestDICEArchive {
    NSURL *_url;
    CFStringRef _uti;
    NSArray *_entries;

}

+ (instancetype)archiveWithEntries:(NSArray<id<DICEArchiveEntry>> *)entries archiveUrl:(NSURL *)url archiveUti:(CFStringRef)uti
{
    return [[self alloc] initWithEntries:entries archiveUrl:url archiveUti:uti];
}

- (instancetype)initWithEntries:(NSArray *)entries archiveUrl:(NSURL *)url archiveUti:(CFStringRef)uti
{
    self = [super init];

    _url = url;
    _uti = uti;
    _entries = entries;

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

- (void)enumerateEntriesUsingBlock:(void (^)(id<DICEArchiveEntry>))block error:(NSError **)error
{
    for (id<DICEArchiveEntry> entry in _entries) {
        block(entry);
    }
}

@end


@implementation TestDICEArchiveEntry {
    NSString *_name;
    archive_size_t _sizeInArchive;
    archive_size_t _sizeExtracted;
}

+ (instancetype)entryWithName:(NSString *)name sizeInArchive:(archive_size_t)inArchive sizeExtracted:(archive_size_t)extracted
{
    return [[self alloc] initWithName:name sizeInArchive:inArchive sizeExtracted:extracted];
}

- (instancetype)initWithName:(NSString *)name sizeInArchive:(archive_size_t)inArchive sizeExtracted:(archive_size_t)extracted
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

- (archive_size_t)archiveEntrySizeExtracted
{
    return _sizeExtracted;
}

- (archive_size_t)archiveEntrySizeInArchive
{
    return _sizeInArchive;
}

- (NSDate *)archiveEntryDate
{
    return [NSDate date];
}


@end
