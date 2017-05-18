//
//  FileOperations.h
//  DICE
//
//  Created by Robert St. John on 8/3/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#ifndef DICE_FileOperations_h
#define DICE_FileOperations_h


#import <Foundation/Foundation.h>


@interface FileOperation : NSOperation
{
    @protected
    NSError *_error;
}

@property (readonly, nonnull) NSFileManager *fileManager;

- (nullable instancetype)initWithFileMananger:(nonnull NSFileManager *)fileManager;

- (nullable NSError *)error;

@end


@interface MkdirOperation : FileOperation

/**
 the URL of the directory to create; the operation will not be ready until
 this property is non-nil
 */
@property (nullable, nonatomic) NSURL *dirUrl;
@property (readonly) BOOL dirWasCreated;
@property (readonly) BOOL dirExisted;

- (nullable instancetype)initWithDirUrl:(nullable NSURL *)dirUrl fileManager:(nonnull NSFileManager *)fileManager;

@end


@interface MoveFileOperation : FileOperation

@property (nullable, nonatomic) NSURL *sourceUrl;
@property (nullable, nonatomic) NSURL *destUrl;
@property (readonly) BOOL fileWasMoved;

- (nullable instancetype)initWithSourceUrl:(nullable NSURL *)sourceUrl destUrl:(nullable NSURL *)destUrl fileManager:(nonnull NSFileManager *)fileManager;

@end


@interface DeleteFileOperation : FileOperation

@property (nullable, nonatomic) NSURL *fileUrl;
@property (readonly) BOOL fileWasDeleted;

- (nullable instancetype)initWithFileUrl:(nullable NSURL *)fileUrl fileManager:(nonnull NSFileManager *)fileManager;

@end


#endif
