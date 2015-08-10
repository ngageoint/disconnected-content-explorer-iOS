//
//  UnzipOperation.m
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "UnzipOperation.h"


@implementation UnzipOperation

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

- (instancetype)initWithZipFile:(ZipFile *)zipFile destDir:(NSURL *)destDir
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

    return self;
}

- (void)main
{
    if (self.cancelled) {
        return;
    }
    
    @autoreleasepool {
        // TODO: do it
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

    BOOL wasReady = self.isReady;
    NSString *destDirKey = NSStringFromSelector(@selector(destDir));
    NSString *isReadyKey = NSStringFromSelector(@selector(isReady));

    [self willChangeValueForKey:destDirKey];
    if ((!wasReady && destDir) || (wasReady && !destDir)) {
        [self willChangeValueForKey:isReadyKey];
    }

    _destDir = destDir;

    [self didChangeValueForKey:destDirKey];
    if (self.isReady == !wasReady) {
        [self didChangeValueForKey:isReadyKey];
    }
}

@end
