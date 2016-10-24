//
// Created by Robert St. John on 6/23/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


typedef void (^KVOBlock)(NSString * _Nonnull keyPath, id _Nonnull target, NSDictionary<NSString *, id> * _Nonnull kvoInfo, void * _Nullable context);


@interface KVOObservation : NSObject

@property (nonnull, readonly) id target;
@property (nonnull, readonly) NSString *keyPath;
@property (nullable, readonly) void *context;
@property (nonnull, readonly) NSDictionary<NSString *, id> *change;
@property (nullable, readonly) id oldValue;
@property (nullable, readonly) id newValue;
@property (readonly) BOOL isPrior;
@property (readonly) BOOL wasMainThread;

- (nullable instancetype)initWithTarget:(nonnull id)target keyPath:(nonnull NSString *)keyPath context:(nullable void *)context change:(nullable NSDictionary<NSString *, id> *)change;

@end


@interface KVOBlockObserver : NSObject

+ (nullable instancetype)recordObservationsOfKeyPath:(nonnull NSString *)keyPath ofObject:(nonnull id)target options:(NSKeyValueObservingOptions)options;

@property (copy, nullable, readonly) KVOBlock observingBlock;
@property (nonnull, readonly) NSMutableArray<KVOObservation *> *observations;

- (nullable instancetype)initWithBlock:(nullable KVOBlock)block;
- (nullable instancetype)observeKeyPath:(nonnull NSString *)keyPath ofObject:(nonnull id)target inContext:(nullable void *)context options:(NSKeyValueObservingOptions)options;

@end
