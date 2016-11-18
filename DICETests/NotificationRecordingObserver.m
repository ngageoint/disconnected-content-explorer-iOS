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
    _wasMainThread = NSThread.isMainThread;

    return self;
}

@end


@implementation NotificationRecordingObserver
{
    void (^_block)(NSNotification *);
}

+ (instancetype)observe:(NSString *)name on:(NSNotificationCenter *)center from:(id)sender withBlock:(void (^)(NSNotification *))block
{
    return [[[NotificationRecordingObserver alloc] initWithBlock:block] observe:name on:center from:sender];
}

- (instancetype)initWithBlock:(void (^)(NSNotification *))block
{
    if (!(self = [super init])) {
        return nil;
    }

    _block = block;
    _received = [[NSMutableArray alloc] init];

    return self;
}

- (instancetype)observe:(NSString *)name on:(NSNotificationCenter *)center from:(id)sender
{
    [center addObserver:self selector:@selector(notify:) name:name object:sender];
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
