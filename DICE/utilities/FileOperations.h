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

@property (readonly) NSFileManager *fileManager;

- (instancetype)initWithFileMananger:(NSFileManager *)fileManager;

@end




@interface MkdirOperation : FileOperation

/**
 the URL of the directory to create; the operation will not be ready until
 this property is non-nil
 */
@property (nonatomic) NSURL *dirUrl;
@property (readonly) BOOL dirWasCreated;
@property (readonly) BOOL dirExisted;

- (instancetype)initWithDirUrl:(NSURL *)dirUrl fileManager:(NSFileManager *)fileManager;

@end




@interface DeleteFileOperation : FileOperation

@property (readonly) NSURL *fileUrl;
@property (readonly) BOOL fileWasDeleted;

- (instancetype)initWithFileUrl:(NSURL *)fileUrl fileManager:(NSFileManager *)fileManager;

@end


#endif
