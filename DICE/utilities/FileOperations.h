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

@property (readonly) NSURL *dirUrl;

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
