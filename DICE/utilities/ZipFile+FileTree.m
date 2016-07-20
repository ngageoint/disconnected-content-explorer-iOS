//
// Created by Robert St. John on 7/19/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "ZipFile+FileTree.h"
#import "FileInZipInfo.h"


@implementation FileInZipInfo (FileListingEntry)

- (NSString *)fileListing_path
{
    return self.name;
}

- (NSUInteger)fileListing_size
{
    return self.length;
}

@end


@interface ZipFileEnumerator : NSEnumerator<id<FileListingEntry>>
@end

@implementation ZipFileEnumerator {
    ZipFile *_zipFile;
}

- (instancetype)initWithZipFile:(ZipFile *)zipFile
{
    if (!(self = [super init])) {
        return nil;
    }

    _zipFile = zipFile;

    return self;
}



@end


@implementation ZipFile (FileTree)

- (NSEnumerator<id<FileListingEntry>> *)fileTree_enumerateFiles
{
    return nil;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained[])buffer count:(NSUInteger)len
{
    return 0;
}

@end