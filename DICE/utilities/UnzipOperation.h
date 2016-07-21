//
//  UnzipOperation.h
//  DICE
//
//  Created by Robert St. John on 6/4/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "OZZipFile.h"


@class UnzipOperation;


@protocol UnzipDelegate <NSObject>

/**
 UnzipOperation calls this method when the percentage of extracted content increases.
 This will be at least once, and at most 100 calls.  UnzipOperation will always
 send this message on the main thread.
 
 @param op the UnzipOperation that is sending the message
 @param percent the percentage of uncompressed bytes that the operation has written
 */
- (void)unzipOperation:(UnzipOperation *)op didUpdatePercentComplete:(NSUInteger)percent;

@end


@interface UnzipOperation : NSOperation

@property (nonatomic, readonly) OZZipFile *zipFile;
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

- (instancetype)initWithZipFile:(OZZipFile *)zipFile destDir:(NSURL *)destDir fileManager:(NSFileManager *)fileManager;

@end
