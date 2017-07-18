//
// Created by Robert St. John on 8/12/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol DICEArchive;


@protocol DICEArchiveEntry <NSObject>

- (nonnull NSString *)archiveEntryPath;
- (uint64_t)archiveEntrySizeExtracted;
- (uint64_t)archiveEntrySizeInArchive;
- (NSDate *)archiveEntryDate;

@end


@protocol DICEArchive <NSObject>

- (nonnull NSURL *)archiveUrl;
- (nonnull CFStringRef)archiveUTType;

- (uint64_t)calculateArchiveSizeExtractedWithError:(NSError * _Nullable * _Nullable)error;

- (void)enumerateEntriesUsingBlock:(void (^_Nonnull)(_Nullable id<DICEArchiveEntry>))block error:(NSError * _Nullable * _Nullable)error;

// TODO: add these later if necessary
//- (nullable id<DICEArchiveEntry>)seekToFirstArchiveEntry;
//- (nullable id<DICEArchiveEntry>)seekToNextArdhiveEntry;
- (BOOL)openCurrentArchiveEntryWithError:(NSError * _Nullable * _Nullable)error;

/**
 * Read the lesser of the given buffer's capacity or bytes available from the current entry.
 *
 * @param buffer an NSMutableData to store the bytes read
 * @return the number of bytes read; 0 if the end of the current entry has been reached
 */
- (NSUInteger)readCurrentArchiveEntryToBuffer:(NSMutableData *)buffer error:(NSError **)error;

- (BOOL)closeCurrentArchiveEntryWithError:(NSError **)error;

- (BOOL)closeArchiveWithError:(NSError **)error;

@end


@protocol DICEArchiveFactory <NSObject>

- (nullable id<DICEArchive>)createArchiveForResource:(nonnull NSURL *)archiveResource withUti:(nullable CFStringRef)archiveResourceUti;

@end
