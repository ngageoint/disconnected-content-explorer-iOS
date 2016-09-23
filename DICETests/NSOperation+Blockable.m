//
// Created by Robert St. John on 6/2/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "NSOperation+Blockable.h"
#import <JGMethodSwizzler/JGMethodSwizzler.h>
#import <objc/runtime.h>
#import <objc/message.h>


@implementation NSOperation (Blockable)

static void *kBlocked;
static void *kBlockLock;

+ (void)load
{
    NSLog(@"loading Blockable NSOperation category %@", self);

    kBlocked = &kBlocked;
    kBlockLock = &kBlockLock;

    [self swizzleInstanceMethod:@selector(init) withReplacement:JGMethodReplacementProviderBlock {
        return ^ NSOperation * (__unsafe_unretained NSOperation *self) {
            self = JGOriginalImplementation(NSOperation *);
            objc_setAssociatedObject(self, kBlockLock, [[NSCondition alloc] init], OBJC_ASSOCIATION_RETAIN);
            [self setBlocked:NO];
            [self swizzleMain_Blockable];
            return self;
        };
    }];
}

- (void)swizzleMain_Blockable
{
    NSLog(@"swizzling main to blockable main for %@", self);

    [self swizzleMethod:@selector(main) withReplacement:JGMethodReplacementProviderBlock {
        return JGMethodReplacement(void, NSOperation *) {
            [self waitUntilUnblocked];
            JGOriginalImplementation(void);
        };
    }];
}

- (BOOL)blocked
{
    NSNumber *blocked = objc_getAssociatedObject(self, kBlocked);
    BOOL blockedBool = [blocked boolValue];
    return blockedBool;
}

- (void)setBlocked:(BOOL)blocked
{
    objc_setAssociatedObject(self, kBlocked, @(blocked), OBJC_ASSOCIATION_COPY);
}

- (NSCondition *)blockLock
{
    return objc_getAssociatedObject(self, kBlockLock);
}

- (instancetype)block {
    [self.blockLock lock];
    self.blocked = YES;
    [self.blockLock unlock];
    return self;
}

- (instancetype)unblock {
    [self.blockLock lock];
    self.blocked = NO;
    [self.blockLock signal];
    [self.blockLock unlock];
    return self;
}

- (void)waitUntilUnblocked {
    [self.blockLock lock];
    while (self.blocked) {
        [self.blockLock wait];
    }
    [self.blockLock unlock];
}

@end
