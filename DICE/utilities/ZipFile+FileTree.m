//
// Created by Robert St. John on 7/19/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "ZipFile+FileTree.h"
#import "OZZipFile+Standard.h"


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


@implementation OZZipFile (FileTree)

- (NSEnumerator<id<FileListingEntry>> *)fileTree_enumerateFiles
{
    return [[self listFileInZipInfos] objectEnumerator];
}

@end