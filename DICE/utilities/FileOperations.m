//
//  NSObject+FileOperations_m.m
//  DICE
//
//  Created by Robert St. John on 8/3/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "FileOperations.h"


@implementation FileOperation

- (instancetype)initWithFileMananger:(NSFileManager *)fileManager
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _fileManager = fileManager;

    return self;
}

- (NSError *)error
{
    return _error;
}

@end



@implementation MkdirOperation


+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keys = [super keyPathsForValuesAffectingValueForKey:key];

    NSString *isReadyKey = NSStringFromSelector(@selector(isReady));
    if ([isReadyKey isEqualToString:key]) {
        keys = [keys setByAddingObject:NSStringFromSelector(@selector(dirUrl))];
    }

    return keys;
}

+ (BOOL)automaticallyNotifiesObserversOfDirUrl
{
    return NO;
}

- (instancetype)initWithDirUrl:(NSURL *)dirUrl fileManager:(NSFileManager *)fileManager
{
    self = [super initWithFileMananger:fileManager];
    if (!self) {
        return nil;
    }

    _dirUrl = dirUrl;

    return self;
}

- (BOOL)isReady
{
    /*
     * include isCancelled in readiness criteria because if the operation is cancelled before
     * ever moving to the ready state, an NSOperationQueue will never remove the operation.
     * this ensures the operation gets to the ready state when calling cancel before execution
     * begins and trigger an NSOperationQueue to remove the cancelled operation.
     */
    return (self.dirUrl != nil || self.isCancelled) && super.isReady;
}

- (void)setDirUrl:(NSURL *)dirUrl
{
    if (self.executing) {
        [NSException raise:@"IllegalStateException" format:@"cannot change dirUrl after MkdirOperation has started"];
    }

    if (dirUrl == self.dirUrl) {
        return;
    }

    NSString *dirUrlKey = NSStringFromSelector(@selector(dirUrl));

    [self willChangeValueForKey:dirUrlKey];

    _dirUrl = dirUrl;

    [self didChangeValueForKey:dirUrlKey];
}

- (void)main
{
    @autoreleasepool {
        BOOL isDir;
        BOOL exists = [self.fileManager fileExistsAtPath:self.dirUrl.path isDirectory:&isDir];
        
        if (exists) {
            if (isDir) {
                _dirExisted = YES;
                return;
            }
            _dirWasCreated = NO;
            return;
        }

        _dirWasCreated = [self.fileManager createDirectoryAtURL:self.dirUrl withIntermediateDirectories:YES attributes:nil error:NULL];
    }
}

@end


@implementation MoveFileOperation

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    if ([key isEqualToString:NSStringFromSelector(@selector(isReady))]) {
        return NO;
    }
    if ([key isEqualToString:NSStringFromSelector(@selector(sourceUrl))]) {
        return NO;
    }
    if ([key isEqualToString:NSStringFromSelector(@selector(destUrl))]) {
        return NO;
    }
    return [super automaticallyNotifiesObserversForKey:key];
}

- (instancetype)initWithSourceUrl:(NSURL *)sourceUrl destUrl:(NSURL *)destUrl fileManager:(NSFileManager *)fileManager
{
    if (!(self = [super initWithFileMananger:fileManager])) {
        return nil;
    }

    _sourceUrl = sourceUrl;
    _destUrl = destUrl;

    return self;
}

- (instancetype)initWithSourceUrl:(NSURL *)sourceUrl destDirUrl:(NSURL *)destDirUrl fileManager:(NSFileManager *)fileManager
{
    return [[self initWithSourceUrl:sourceUrl destUrl:nil fileManager:fileManager] setDestDirUrl:destDirUrl];
}

- (instancetype)createDestDirs:(BOOL)mkdirs
{
    if (self.isExecuting || self.isFinished) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot set createDestDirs flag whlie or after executing"];
    }
    _createDestDirs = mkdirs;
    return self;
}

- (instancetype)setDestDirUrl:(NSURL *)destDirUrl
{
    self.destUrl = [destDirUrl URLByAppendingPathComponent:self.sourceUrl.lastPathComponent];
    return self;
}

- (void)setSourceUrl:(NSURL *)sourceUrl
{
    if (self.isExecuting || self.isFinished) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot set sourceUrl while or after executing"];
    }

    if ([sourceUrl isEqual:self.sourceUrl]) {
        return;
    }

    [self willChangeValueForKey:NSStringFromSelector(@selector(sourceUrl))];
    if (self.destUrl) {
        [self willChangeValueForKey:NSStringFromSelector(@selector(isReady))];
    }

    _sourceUrl = sourceUrl;

    if (self.destUrl) {
        [self didChangeValueForKey:NSStringFromSelector(@selector(isReady))];
    }
    [self didChangeValueForKey:NSStringFromSelector(@selector(sourceUrl))];
}

- (void)setDestUrl:(NSURL *)destUrl
{
    if (self.isExecuting || self.isFinished) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot set destUrl while or after executing"];
    }

    if ([destUrl isEqual:self.destUrl]) {
        return;
    }

    [self willChangeValueForKey:NSStringFromSelector(@selector(destUrl))];
    if (self.sourceUrl) {
        [self willChangeValueForKey:NSStringFromSelector(@selector(isReady))];
    }

    _destUrl = destUrl;

    if (self.sourceUrl) {
        [self didChangeValueForKey:NSStringFromSelector(@selector(isReady))];
    }
    [self didChangeValueForKey:NSStringFromSelector(@selector(destUrl))];
}

- (BOOL)isReady
{
    return super.isReady && (self.isCancelled || (self.sourceUrl != nil && self.destUrl != nil));
}

- (void)main
{
    @autoreleasepool {
        NSError *err;
        if (_createDestDirs) {
            NSURL *destDir = [self.destUrl URLByDeletingLastPathComponent];
            if (![self.fileManager createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:&err]) {
                _error = err;
                return;
            }
        }
        _fileWasMoved = [self.fileManager moveItemAtURL:self.sourceUrl toURL:self.destUrl error:&err];
        _error = err;
    }
}

@end


@implementation DeleteFileOperation

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keys = [super keyPathsForValuesAffectingValueForKey:key];

    NSString *isReadyKey = NSStringFromSelector(@selector(isReady));
    if ([isReadyKey isEqualToString:key]) {
        keys = [keys setByAddingObject:NSStringFromSelector(@selector(fileUrl))];
    }

    return keys;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
    if ([key isEqualToString:NSStringFromSelector(@selector(fileUrl))]) {
        return NO;
    }
    return [super automaticallyNotifiesObserversForKey:key];
}

- (instancetype)initWithFileUrl:(NSURL *)fileUrl fileManager:(NSFileManager *)fileManager
{
    self = [super initWithFileMananger:fileManager];

    if (!self) {
        return nil;
    }

    _fileUrl = fileUrl;

    return self;
}

- (void)setFileUrl:(NSURL *)fileUrl
{
    if (self.isExecuting || self.isFinished) {
        [NSException raise:NSInternalInconsistencyException format:@"cannot change file url while or after executing"];
    }

    if (fileUrl == self.fileUrl || [fileUrl isEqual:self.fileUrl]) {
        return;
    }

    NSString *fileUrlKey = NSStringFromSelector(@selector(fileUrl));
    [self willChangeValueForKey:fileUrlKey];
    _fileUrl = fileUrl;
    [self didChangeValueForKey:fileUrlKey];
}

- (BOOL)isReady
{
    return super.isReady && (self.isCancelled || self.fileUrl != nil);
}

- (void)main
{
    @autoreleasepool {
        _fileWasDeleted = [self.fileManager removeItemAtURL:self.fileUrl error:nil];
    }
}

@end
