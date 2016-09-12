//
// Created by Robert St. John on 8/12/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef unsigned long long int archive_size_t;


@protocol DICEArchiveEntry <NSObject>

- (nonnull NSString *)archiveEntryPath;
- (archive_size_t)archiveEntrySizeExtracted;
- (archive_size_t)archiveEntrySizeInArchive;

@end


@protocol DICEArchive <NSObject>

- (nonnull NSURL *)archiveUrl;
- (nonnull CFStringRef)archiveUTType;
- (void)enumerateEntriesUsingBlock:(void (^_Nonnull)(_Nonnull id<DICEArchiveEntry>))block;

@end
