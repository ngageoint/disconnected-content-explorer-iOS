//
// Created by Robert St. John on 7/19/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol FileListingEntry <NSObject>

- (NSString *)fileListing_path;
- (NSUInteger)fileListing_size;

@end


@protocol FileTree <NSObject>

- (NSEnumerator<id<FileListingEntry>> *)fileTree_enumerateFiles;
- (id<FileListingEntry>)fileTree_findBaseName:(NSString *)baseName;

@end


