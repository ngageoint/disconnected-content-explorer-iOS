//
// Created by Robert St. John on 6/16/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "NotificationRecordingObserver.h"


@implementation ReceivedNotification

- (instancetype)initWithNotification:(NSNotification *)notification
{
    if (!(self = [super init])) {
        return nil;
    }

    _notification = notification;
    _wasMainThread = [NSThread currentThread] == [NSThread mainThread];

    return self;
}

@end


@implementation NotificationRecordingObserver
{
    void (^_block)(NSNotification *);
}

+ (instancetype)observe:(NSString *)name on:(NSNotificationCenter *)center from:(id)sender withBlock:(void (^)(NSNotification *))block
{
    NotificationRecordingObserver *observer = [[NotificationRecordingObserver alloc] initWithBlock:block];
    [center addObserver:observer selector:@selector(notify:) name:name object:sender];
    return observer;
}

- (instancetype)initWithBlock:(void (^)(NSNotification *))block
{
    if (!(self = [super init])) {
        return nil;
    }

    _received = [[NSMutableArray alloc] init];
    _block = block;

    return self;
}

- (void)notify:(NSNotification *)notification
{
    [self.received addObject:[[ReceivedNotification alloc] initWithNotification:notification]];
    if (_block) {
        _block(notification);
    }
}

@end