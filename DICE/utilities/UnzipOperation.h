//
//  UnzipOperation.h
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface UnzipOperation : NSOperation

+ (UnzipOperation *)unzipFile:(NSURL *)zipFile toDir:(NSURL *)destDir onQueue:(NSOperationQueue *)queue;

@property (strong, nonatomic, readonly) NSURL *zipFile;
@property (strong, nonatomic, readonly) NSURL *destDir;

@end
