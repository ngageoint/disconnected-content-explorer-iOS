//
// Created by Robert St. John on 6/16/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface ReceivedNotification : NSObject

@property (readonly) BOOL wasMainThread;
@property (readonly) NSNotification *notification;

- (instancetype)initWithNotification:(NSNotification *)notification;

@end


@interface NotificationRecordingObserver : NSObject

+ (instancetype)observe:(NSString *)name on:(NSNotificationCenter *)center from:(id)sender withBlock:(void(^)(NSNotification *))block;

@property (readonly) NSMutableArray<ReceivedNotification *> *received;

- (instancetype)initWithBlock:(void(^)(NSNotification *))block;
- (void)notify:(NSNotification *)notification;

@end