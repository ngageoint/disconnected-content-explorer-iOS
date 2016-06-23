//
// Created by Robert St. John on 6/23/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "KVOBlockObserver.h"


@implementation KVOBlockObserver {

}

- (instancetype)initWithBlock:(void (^)(NSString *keyPath, id object, NSDictionary<NSString *, id> *change, void *context))block
{
    if (!(self = [super init])) {
        return nil;
    }

    _observingBlock = block;

    return self;
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)context
{
    self.observingBlock(keyPath, object, change, context);
}


@end