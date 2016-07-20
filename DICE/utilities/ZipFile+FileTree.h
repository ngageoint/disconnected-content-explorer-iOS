//
// Created by Robert St. John on 7/19/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZipFile.h"
#import "FileInZipInfo.h"
#import "FileTree.h"

@interface FileInZipInfo (FileTree) <FileListingEntry>
@end

@interface ZipFile (FileTree) <FileTree>
@end


