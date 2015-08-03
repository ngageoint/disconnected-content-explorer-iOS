//
//  SimpleFileManager.h
//  DICE
//
//  Created by Robert St. John on 6/5/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol FileInfo <NSObject>

@property (readonly, nonatomic) NSURL *path;
@property (readonly, nonatomic) BOOL isDirectory;
@property (readonly, nonatomic) BOOL isRegularFile;

@end


@protocol SimpleFileManager <NSObject>

- (id<FileInfo>)infoForPath:(NSURL *)path;
- (NSURL *)createTempDir;
- (BOOL)deleteFileAtPath:(NSURL *)path;

@end
