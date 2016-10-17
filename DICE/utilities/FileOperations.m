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




@implementation DeleteFileOperation

- (instancetype)initWithFileUrl:(NSURL *)fileUrl fileManager:(NSFileManager *)fileManager
{
    self = [super initWithFileMananger:fileManager];

    if (!self) {
        return nil;
    }

    _fileUrl = fileUrl;

    return self;
}

- (void)main
{
    @autoreleasepool {
        _fileWasDeleted = [self.fileManager removeItemAtURL:self.fileUrl error:nil];
    }
}

@end
