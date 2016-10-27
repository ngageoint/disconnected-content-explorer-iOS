//
//  TestOperationQueue.m
//  DICE
//
//  Created by Robert St. John on 9/22/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "TestOperationQueue.h"

@implementation TestOperationQueue

- (void)addOperation:(NSOperation *)op
{
    if (self.onAddOperation) {
        self.onAddOperation(op);
    }
    [super addOperation:op];
}

- (void)addOperations:(NSArray<NSOperation *> *)ops waitUntilFinished:(BOOL)wait
{
    if (self.onAddOperation) {
        for (NSOperation *op in ops) {
            self.onAddOperation(op);
        }
    }
    [super addOperations:ops waitUntilFinished:wait];
}

@end
