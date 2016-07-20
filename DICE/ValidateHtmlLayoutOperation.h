//
//  ValidateHtmlLayoutOperation.h
//  DICE
//
//  Created by Robert St. John on 12/21/15.
//  Copyright © 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ZipFile.h"
#import "FileTree.h"


@interface ValidateHtmlLayoutOperation : NSOperation

@property (readonly) ZipFile *zipFile;
@property (readonly) NSEnumerator<id<FileListingEntry>> *fileListing;

/**
 whether the zip contains a valid index.html in a valid location;
 set after the operation finishes
 */
@property (readonly) BOOL isLayoutValid;
/**
 the path of the directory that contains index.html whithin the zip file;
 set after the operation finishes; can be the empty string
 */
@property (readonly) NSString *indexDirPath;
/**
 whether the zip contains a json descriptor file with extra information
 about the report
 */
@property (readonly) BOOL hasDescriptor;
/**
 the path of the json descriptor file within the zip file; nil if one is
 not present
 */
@property (readonly) NSString *descriptorPath;

- (instancetype)initWithZipFile:(ZipFile *)zipFile;
- (instancetype)initWithFileListing:(NSEnumerator<id<FileListingEntry>> *)files;

@end
