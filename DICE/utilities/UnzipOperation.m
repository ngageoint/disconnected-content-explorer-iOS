//
//  UnzipOperation.m
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "UnzipOperation.h"
#import "ZipException.h"
#import "FileInZipInfo.h"
#import "ZipReadStream.h"


@implementation UnzipOperation
{
    NSUInteger _bufferSize;
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

- (instancetype)initWithZipFile:(ZipFile *)zipFile destDir:(NSURL *)destDir fileManager:(NSFileManager *)fileManager
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
    _wasSuccessful = NO;

    return self;
}

- (void)main
{
    if (self.isCancelled) {
        return;
    }
    
    @autoreleasepool {
        _bufferSize = 1 << 16; // 64kB
        _entryBuffer = [NSMutableData dataWithLength:(_bufferSize)];

        @try {
            [self commenceUnzip];
        }
        @catch (ZipException *e) {
            // TODO: this catch block does not activate in tests for some reason - maddening
            _wasSuccessful = NO;
            _errorMessage = [NSString stringWithFormat:@"Error reading zip file: %@", e.reason];
        }
        @catch (NSException *e) {
            e = (ZipException *)e;
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
            [_entryBuffer release];
            [self.zipFile close];
        }
    }
}

- (BOOL)isReady
{
    return self.destDir != nil && super.ready;
}

- (void)setDestDir:(NSURL *)destDir
{
    if (self.executing) {
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

- (void)commenceUnzip
{
    NSMutableDictionary *dirDates = [NSMutableDictionary dictionary];

    [self.zipFile goToFirstFileInZip];
    do {
        FileInZipInfo *entry = [self.zipFile getCurrentFileInZipInfo];
        NSURL *entryUrl = [self.destDir URLByAppendingPathComponent:entry.name];
        BOOL entryIsDir = [entry.name hasSuffix:@"/"];
        if (entryIsDir) {
            [self createDirectoryForEntry:entry atUrl:entryUrl];
            [dirDates setObject:entry.date forKey:entryUrl.path];
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

- (void)createDirectoryForEntry:(FileInZipInfo *)entry atUrl:(NSURL *)dir
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

- (void)writeFileForEntry:(FileInZipInfo *)entry atUrl:(NSURL *)file
{
    BOOL created = [self.fileManager createFileAtPath:file.path contents:nil attributes:nil];
    if (!created) {
        [self cancel];
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:file.path];
    ZipReadStream *read = [self.zipFile readCurrentFileInZip];
    NSUInteger count;
    while ((count = [read readDataWithBuffer:_entryBuffer])) {
        _entryBuffer.length = count;
        [handle writeData:_entryBuffer];
        _entryBuffer.length = _bufferSize;
    }
    [read finishedReading];
    [handle closeFile];
}

@end
