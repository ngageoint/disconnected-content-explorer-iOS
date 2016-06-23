//
// Created by Robert St. John on 6/23/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface KVOBlockObserver : NSObject

@property (copy, readonly) void (^observingBlock)(NSString *, id, NSDictionary *, void *);

- (instancetype)initWithBlock:(void (^)(NSString *, id, NSDictionary *, void *))block;

@end