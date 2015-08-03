//
//  DeleteFileOperation.h
//  DICE
//
//  Created by Robert St. John on 7/23/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DeleteFileOperation : NSOperation

@property (nonatomic, readonly) NSURL *file;

- (instancetype)initWithFile:(NSURL *)file;

@end
