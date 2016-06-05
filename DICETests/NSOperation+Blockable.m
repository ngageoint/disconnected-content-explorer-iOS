//
// Created by Robert St. John on 6/2/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "NSOperation+Blockable.h"

#import <objc/runtime.h>
#import <objc/message.h>


@implementation NSOperation (Blockable)

static char kBlocked;
static char kBlockLock;

static SEL blockableMainSel;
static IMP blockableMainImp;

+ (void)load
{
    NSLog(@"loading %@", self);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL origInitSel = @selector(init);
        SEL blockableInitSel =  @selector(init_Blockable);
        Method origInit = class_getInstanceMethod(self, origInitSel);
        Method blockableInit = class_getInstanceMethod(self, blockableInitSel);
        BOOL added = class_addMethod([self class], origInitSel, method_getImplementation(blockableInit), method_getTypeEncoding(blockableInit));
        if (added) {
            class_replaceMethod([self class], blockableInitSel, method_getImplementation(origInit), method_getTypeEncoding(origInit));
        }
        else {
            method_exchangeImplementations(origInit, blockableInit);
        }

        blockableMainSel = sel_registerName("Blockable_main");
        blockableMainImp = imp_implementationWithBlock(^(__weak id self) {
            [self waitUntilUnblocked];
            ((void(*)(id, SEL))objc_msgSend)(self, blockableMainSel);
        });
    });
}

- (instancetype)init_Blockable
{
    self = [self init_Blockable];
    NSLog(@"init_Blockable %@:%@", self, [self class]);
    objc_setAssociatedObject(self, &kBlockLock, [[NSCondition alloc] init], OBJC_ASSOCIATION_RETAIN);
    [self swizzleMain_Blockable];
    return self;
}

- (void)swizzleMain_Blockable
{
    SEL origSel = @selector(main);

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList([self class], &methodCount);
    for (int i = 0; i < methodCount; i++) {
        Method m = *(methods + i);
        SEL sel = method_getName(m);
        if (sel_isEqual(sel, blockableMainSel)) {
            NSLog(@"%@ already has %s", [self class], sel_getName(blockableMainSel));
            return;
        }
    }
    free(methods);

    NSLog(@"swizzling main to blockable main for %@", [self class]);
    Method main = class_getInstanceMethod([self class], origSel);

    const char *enc = method_getTypeEncoding(main);
    BOOL added = class_addMethod([self class], blockableMainSel, blockableMainImp, enc);
    if (added) {
        Method blockableMain = class_getInstanceMethod([self class], blockableMainSel);
        method_exchangeImplementations(main, blockableMain);
    }
}

- (BOOL)blocked
{
    return [objc_getAssociatedObject(self, &kBlocked) boolValue];
}

- (void)setBlocked:(BOOL)blocked
{
    objc_setAssociatedObject(self, &kBlocked, @(blocked), OBJC_ASSOCIATION_COPY);
}

- (NSCondition *)blockLock
{
    return objc_getAssociatedObject(self, &kBlockLock);
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