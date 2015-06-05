//
//  UnzipOperation.h
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SimpleFileManager.h"

@interface UnzipOperation : NSOperation

@property (strong, nonatomic, readonly) NSURL *zipFile;
@property (strong, nonatomic, readonly) NSURL *destDir;

- (instancetype)initWithZipFile:(NSURL *)zipFile destDir:(NSURL *)destDir fileManager:(id<SimpleFileManager>)fileManager;

@end
