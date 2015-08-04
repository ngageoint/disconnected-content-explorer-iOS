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


@interface MkdirOperation : NSOperation

/**
 the URL of the directory to create; the operation will not be ready until
 this property is non-nil
 */
@property (nonatomic) NSURL *dirUrl;
@property (readonly) BOOL dirWasCreated;
@property (readonly) BOOL dirExisted;

- (instancetype)init;
- (instancetype)initWithDirUrl:(NSURL *)dirUrl;

@end


@interface MoveFileOperation : NSOperation

@property (readonly) NSURL *sourcePathUrl;
@property (readonly) NSURL *destPathUrl;

- (instancetype)initWithSourceUrl:(NSURL *)source destUrl:(NSURL *)destUrl;
- (instancetype)initWithSourceUrl:(NSURL *)source destDirUrl:(NSURL *)destDir;

@end



@interface DeleteFileOperation : NSOperation

@property (readonly) NSURL *fileUrl;

- (instancetype)initWithFileUrl:(NSURL *)fileUrl;

@end


#endif
