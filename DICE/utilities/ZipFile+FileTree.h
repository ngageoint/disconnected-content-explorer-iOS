//
// Created by Robert St. John on 7/19/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OZZipFile.h"
#import "OZFileInZipInfo.h"
#import "FileTree.h"

@interface OZFileInZipInfo (FileTree) <FileListingEntry>
@end

@interface OZZipFile (FileTree) <FileTree>
@end


