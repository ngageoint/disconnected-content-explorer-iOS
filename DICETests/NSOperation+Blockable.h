//
// Created by Robert St. John on 6/2/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSOperation (Blockable)

- (instancetype)block;
- (instancetype)unblock;

@end
