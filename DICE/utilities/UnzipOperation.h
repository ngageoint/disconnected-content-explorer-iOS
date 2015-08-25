//
//  UnzipOperation.h
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ZipFile.h"


@class UnzipOperation;


@protocol UnzipDelegate <NSObject>

- (void)unzipOperation:(UnzipOperation *)op didUpdatePercentComplete:(NSUInteger)percent;

@end


@interface UnzipOperation : NSOperation

@property (nonatomic, readonly) ZipFile *zipFile;
@property (nonatomic) NSURL *destDir;
@property (nonatomic, readonly) NSFileManager *fileManager;
/**
 the buffer size in bytes
 */
@property (nonatomic) NSUInteger bufferSize;
@property (nonatomic, weak) id<UnzipDelegate> delegate;
/**
 whether the unzip completed successfully
 */
@property (readonly) BOOL wasSuccessful;
@property (readonly) NSString *errorMessage;

- (instancetype)initWithZipFile:(ZipFile *)zipFile destDir:(NSURL *)destDir fileManager:(NSFileManager *)fileManager;

@end
