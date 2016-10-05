//
// Created by Robert St. John on 6/23/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "KVOBlockObserver.h"


@implementation KVOObservation

- (instancetype)initWithTarget:(id)target keyPath:(NSString *)keyPath context:(void *)context change:(NSDictionary<NSString *,id> *)change
{
    self = [super init];

    _target = target;
    _keyPath = keyPath;
    _context = context;
    _change = change;

    return self;
}

- (id)oldValue
{
    return self.change[NSKeyValueChangeOldKey];
}

- (id)newValue
{
    return self.change[NSKeyValueChangeNewKey];
}

@end

@implementation KVOBlockObserver {

}

- (instancetype)observeKeyPath:(NSString *)keyPath ofObject:(id)target inContext:(void *)context options:(NSKeyValueObservingOptions)options
{
    [target addObserver:self forKeyPath:keyPath options:options context:context];
    return self;
}

- (instancetype)initWithBlock:(KVOBlock)block
{
    if (!(self = [super init])) {
        return nil;
    }

    _observingBlock = block;
    _observations = [NSMutableArray array];

    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *, id> *)change context:(void *)context
{
    @synchronized (self) {
        [self.observations addObject:[[KVOObservation alloc] initWithTarget:object keyPath:keyPath context:context change:change]];
    }
    if (self.observingBlock) {
        self.observingBlock(keyPath, object, change, context);
    }
}


@end
