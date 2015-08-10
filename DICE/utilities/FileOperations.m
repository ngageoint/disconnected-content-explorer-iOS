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

    if ([key isEqualToString:@"ready"]) {
        keys = [keys setByAddingObject:@"dirUrl"];
    }

    return keys;
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
    return self.dirUrl != nil && super.ready;
}

- (void)setDirUrl:(NSURL *)dirUrl
{
    if (self.executing) {
        [NSException raise:@"IllegalStateException" format:@"cannot change dirUrl after MkdirOperation has started"];
    }

    _dirUrl = dirUrl;
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

        _dirWasCreated = [self.fileManager createDirectoryAtURL:self.dirUrl withIntermediateDirectories:NO attributes:nil error:NULL];
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
        BOOL removed = [self.fileManager removeItemAtURL:self.fileUrl error:nil];
        if (!removed) {
            // TODO: something
        }
    }
}

@end
