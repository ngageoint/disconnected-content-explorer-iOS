//
//  UnzipOperation.h
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ZipFile.h"

@interface UnzipOperation : NSOperation

@property (readonly) ZipFile *zipFile;
@property (nonatomic) NSURL *destDir;
/**
 whether the unzip completed successfully
 */
@property (readonly) BOOL wasSuccessful;

- (instancetype)initWithZipFile:(ZipFile *)zipFile destDir:(NSURL *)destDir;

@end
