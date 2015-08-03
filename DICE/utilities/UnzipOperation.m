//
//  UnzipOperation.m
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "UnzipOperation.h"

#import "SimpleFileManager.h"

@implementation UnzipOperation

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keys = [super keyPathsForValuesAffectingValueForKey:key];

    if ([key isEqualToString:@"ready"]) {
        keys = [keys setByAddingObject:@"destDir"];
    }

    return keys;
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

    _destDir = destDir;
}

@end
