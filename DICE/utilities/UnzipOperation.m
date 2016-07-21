//
//  UnzipOperation.m
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "UnzipOperation.h"
#import "OZZipException.h"
#import "OZZipFile+Standard.h"
#import "OZFileInZipInfo.h"
#import "OZZipReadStream+Standard.h"


@implementation UnzipOperation
{
    NSUInteger _totalUncompressedSize;
    NSUInteger _percentExtracted;
    NSUInteger _bytesExtracted;
    NSMutableData *_entryBuffer;
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

- (instancetype)initWithZipFile:(OZZipFile *)zipFile destDir:(NSURL *)destDir fileManager:(NSFileManager *)fileManager
{
    self = [super init];
    if (!self) {
        return nil;
    }

    if (zipFile == nil) {
        [NSException raise:@"IllegalArgumentException" format:@"zipFile is nil"];
    }

    _zipFile = zipFile;
    _destDir = destDir;
    _fileManager = fileManager;
    _bufferSize = 1 << 16; // 64kB
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
        _entryBuffer = [NSMutableData dataWithLength:(_bufferSize)];

        @try {
            [self calculateTotalSize];
            [self commenceUnzip];
        }
        @catch (OZZipException *e) {
            // TODO: this catch block does not activate in tests for some reason - maddening
            _wasSuccessful = NO;
            _errorMessage = [NSString stringWithFormat:@"Error reading zip file: %@", e.reason];
        }
        @catch (NSException *e) {
            e = (OZZipException *)e;
            if ([@"ZipException" isEqualToString:e.name]) {
                _wasSuccessful = NO;
                _errorMessage = [NSString stringWithFormat:@"Error reading zip file: %@", e.reason];
            }
            else {
                _wasSuccessful = NO;
                _errorMessage = e.reason;
            }
        }
        @finally {
            _entryBuffer.length = 0;
            [self.zipFile close];
        }
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

- (void)setBufferSize:(NSUInteger)bufferSize
{
    if (self.isExecuting) {
        [NSException raise:@"IllegalStateException" format:@"cannot change bufferSize after UnzipOperation has started"];
    }

    _bufferSize = bufferSize;
}

- (void)calculateTotalSize
{
    NSArray *entries = [self.zipFile listFileInZipInfos];
    for (OZFileInZipInfo *entry in entries) {
        _totalUncompressedSize += entry.length;
    }
}

- (void)commenceUnzip
{
    NSMutableDictionary *dirDates = [NSMutableDictionary dictionary];

    [self.zipFile goToFirstFileInZip];
    do {
        OZFileInZipInfo *entry = [self.zipFile getCurrentFileInZipInfo];
        NSURL *entryUrl = [self.destDir URLByAppendingPathComponent:entry.name];
        BOOL entryIsDir = [entry.name hasSuffix:@"/"];
        if (entryIsDir) {
            [self createDirectoryForEntry:entry atUrl:entryUrl];
            dirDates[entryUrl.path] = entry.date;
        }
        else {
            [self writeFileForEntry:entry atUrl:entryUrl];
            NSDictionary *modDate = @{ NSFileModificationDate: entry.date };
            [self.fileManager setAttributes:modDate ofItemAtPath:entryUrl.path error:nil];
        }
    } while (!self.isCancelled && [self.zipFile goToNextFileInZip]);

    if (self.isCancelled) {
        return;
    }

    _wasSuccessful = YES;

    // set the directory mod dates last because to ensure that writing the files
    // while unzipping does not update the mod date
    for (NSString *dirPath in [dirDates keyEnumerator]) {
        NSDictionary *modDate = @{ NSFileModificationDate: dirDates[dirPath] };
        [self.fileManager setAttributes:modDate ofItemAtPath:dirPath error:nil];
    }

    [dirDates removeAllObjects];
}

- (void)createDirectoryForEntry:(OZFileInZipInfo *)entry atUrl:(NSURL *)dir
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

- (void)writeFileForEntry:(OZFileInZipInfo *)entry atUrl:(NSURL *)file
{
    BOOL created = [self.fileManager createFileAtPath:file.path contents:nil attributes:nil];
    if (!created) {
        [self cancel];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:file.path];
    OZZipReadStream *read = [self.zipFile readCurrentFileInZip];
    NSUInteger count;
    while ((count = [read readDataWithBuffer:_entryBuffer])) {
        _entryBuffer.length = count;
        [handle writeData:_entryBuffer];
        _entryBuffer.length = _bufferSize;
        _bytesExtracted += count;
        NSUInteger percent = floor(100.0f * _bytesExtracted / _totalUncompressedSize);
        if (percent > _percentExtracted) {
            _percentExtracted = percent;
            [self sendPercentageUpdate];
        }
    }
    [read finishedReading];
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
