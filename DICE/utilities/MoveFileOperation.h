//
//  MoveFileOperation.h
//  DICE
//
//  Created by Robert St. John on 7/28/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MoveFileOperation : NSOperation

@property (nonatomic, readonly) NSURL *sourcePath;
@property (nonatomic, readonly) NSURL *destPath;

- (instancetype)initWithSourcePath:(NSURL *)source destPath:(NSURL *)destPath;
- (instancetype)initWithSourcePath:(NSURL *)source destDir:(NSURL *)destDir;

@end
