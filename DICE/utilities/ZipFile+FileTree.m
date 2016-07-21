//
// Created by Robert St. John on 7/19/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "ZipFile+FileTree.h"


@implementation OZFileInZipInfo (FileListingEntry)

- (NSString *)fileListing_path
{
    return self.name;
}

- (NSUInteger)fileListing_size
{
    return (NSUInteger)self.length;
}

@end


@interface ZipFileEnumerator : NSEnumerator<id<FileListingEntry>>
@end

@implementation ZipFileEnumerator {
    OZZipFile *_zipFile;
}

- (instancetype)initWithZipFile:(OZZipFile *)zipFile
{
    if (!(self = [super init])) {
        return nil;
    }

    _zipFile = zipFile;

    return self;
}

- (id<FileListingEntry>)nextObject
{
    return nil;
}

- (NSArray<id<FileListingEntry>> *)allObjects
{
    return @[];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained[])buffer count:(NSUInteger)len
{
    return 0;
}

@end


@implementation OZZipFile (FileTree)

- (NSEnumerator<id<FileListingEntry>> *)fileTree_enumerateFiles
{
    return nil;
}

@end