//
//  UnzipOperation.m
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "UnzipOperation.h"
#import "DICEArchive.h"


@implementation UnzipOperation
{
    archive_size_t _totalUncompressedSize;
    NSUInteger _percentExtracted;
    NSUInteger _bytesExtracted;
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keys = [super keyPathsForValuesAffectingValueForKey:key];

    if ([NSStringFromSelector(@selector(isReady)) isEqualToString:key]) {
        keys = [keys setByAddingObject:NSStringFromSelector(@selector(destDir))];
    }

    return keys;
}

+ (BOOL)automaticallyNotifiesObserversOfDestDir
{
    return NO;
}

- (instancetype)initWithArchive:(id<DICEArchive>)archive destDir:(NSURL *)destDir fileManager:(NSFileManager *)fileManager
{
    self = [super init];
    if (!self) {
        return nil;
    }

    if (archive == nil) {
        [NSException raise:@"IllegalArgumentException" format:@"archive is nil"];
    }

    _archive = archive;
    _destDir = destDir;
    _fileManager = fileManager;
    _totalUncompressedSize = 0;
    _percentExtracted = 0;
    _bytesExtracted = 0;
    _wasSuccessful = NO;

    return self;
}

- (void)main
{
    if (self.isCancelled) {
        return;
    }
    
    @autoreleasepool {
        if (!self.buffer) {
            _buffer = [NSMutableData dataWithLength:(1 << 16)];
        }

        [self calculateTotalSize];
        [self commenceUnzip];
        [_archive closeArchiveWithError:NULL];
        self.buffer.length = 0;
    }
}

- (BOOL)isReady
{
    return (self.destDir != nil || self.isCancelled) && super.isReady;
}

- (void)setDestDir:(NSURL *)destDir
{
    if (self.isExecuting) {
        [NSException raise:@"IllegalStateException" format:@"cannot change destDir after UnzipOperation has started"];
    }

    if (destDir == self.destDir) {
        return;
    }

    NSString *destDirKey = NSStringFromSelector(@selector(destDir));

    [self willChangeValueForKey:destDirKey];

    _destDir = destDir;

    [self didChangeValueForKey:destDirKey];
}

- (void)setBuffer:(NSMutableData *)buffer
{
    if (self.isExecuting) {
        [NSException raise:@"IllegalStateException" format:@"cannot change bufferSize after UnzipOperation has started"];
    }

    _buffer = buffer;
}

- (void)calculateTotalSize
{
    _totalUncompressedSize = [_archive calculateArchiveSizeExtractedWithError:NULL];
}

- (void)commenceUnzip
{
    NSMutableDictionary *dirDates = [NSMutableDictionary dictionary];

    [_archive enumerateEntriesUsingBlock:^(id<DICEArchiveEntry> entry) {
        if (self.isCancelled) {
            return;
        }
        NSURL *entryUrl = [self.destDir URLByAppendingPathComponent:entry.archiveEntryPath];
        BOOL entryIsDir = [entry.archiveEntryPath hasSuffix:@"/"];
        if (entryIsDir) {
            [self createDirectoryAtUrl:entryUrl];
            dirDates[entryUrl.path] = entry.archiveEntryDate;
        } else {
            [self writeFileForEntry:entry atUrl:entryUrl];
            NSDictionary *modDate = @{NSFileModificationDate: entry.archiveEntryDate};
            [self.fileManager setAttributes:modDate ofItemAtPath:entryUrl.path error:nil];
        }
    } error:NULL];

    _wasSuccessful = !self.isCancelled;

    // set the directory mod dates last because to ensure that writing the files
    // while unzipping does not update the mod date
    for (NSString *dirPath in [dirDates keyEnumerator]) {
        NSDictionary *modDate = @{ NSFileModificationDate: dirDates[dirPath] };
        [self.fileManager setAttributes:modDate ofItemAtPath:dirPath error:nil];
    }

    [dirDates removeAllObjects];
}

- (void)createDirectoryAtUrl:(NSURL *)dir
{
    BOOL existingFileIsDir = YES;
    if ([self.fileManager fileExistsAtPath:dir.path isDirectory:&existingFileIsDir]) {
        if (!existingFileIsDir) {
            [self cancel];
        }
        return;
    }

    BOOL created = [self.fileManager createDirectoryAtPath:dir.path withIntermediateDirectories:YES attributes:nil error:nil];

    if (!created) {
        [self cancel];
    }
}

- (void)writeFileForEntry:(id<DICEArchiveEntry>)entry atUrl:(NSURL *)file
{
    BOOL created = [self.fileManager createFileAtPath:file.path contents:nil attributes:nil];
    if (!created) {
        _errorMessage = [NSString stringWithFormat:@"Failed to create file to extract archive entry %@", entry.archiveEntryPath];
        [self cancel];
        return;
    }
    NSError *error;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:file error:&error];
    if (error || !handle) {
        NSString *errDesc = @"null file handle";
        if (error) {
            errDesc = error.localizedDescription;
        }
        _errorMessage = [NSString stringWithFormat:@"Failed to open file for writing archive entry %@: %@", entry.archiveEntryPath, errDesc];
        [self cancel];
        return;
    }
    if (![_archive openCurrentArchiveEntryWithError:&error]) {
        _errorMessage = [NSString stringWithFormat:@"Failed to read archive entry %@: %@", entry.archiveEntryPath, error.localizedDescription];
        [self cancel];
        return;
    }

    NSUInteger count;
    while ((count = [_archive readCurrentArchiveEntryToBuffer:self.buffer error:NULL])) {
        _bytesExtracted += count;
        void *bytes = (void *) self.buffer.bytes;
        [handle writeData:[NSData dataWithBytesNoCopy:bytes length:count freeWhenDone:NO]];
        NSUInteger percent = (NSUInteger) floor(100.0f * _bytesExtracted / _totalUncompressedSize);
        if (percent > _percentExtracted) {
            _percentExtracted = percent;
            [self sendPercentageUpdate];
        }
    }
    [_archive closeCurrentArchiveEntryWithError:nil];
    [handle closeFile];
}

- (void)sendPercentageUpdate
{
    if (self.delegate == nil) {
        return;
    }
    NSUInteger percent = _percentExtracted;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate unzipOperation:self didUpdatePercentComplete:percent];
    });
}

@end
