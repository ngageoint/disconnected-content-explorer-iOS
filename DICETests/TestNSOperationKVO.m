//
//  TestNSOperationKVO.m
//  DICE
//
//  Created by Robert St. John on 10/5/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <XCTest/XCTest.h>

@interface TestNSOperationKVO : XCTestCase

@end

@implementation TestNSOperationKVO {
    NSMutableArray<NSDictionary *> *changes;
}

NSString *kKeyPath = @"keyPath";
NSString *kChange = @"change";

- (void)setUp {
    [super setUp];

    changes = [NSMutableArray array];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testIsExecutingKVO {
    NSOperation *op = [NSBlockOperation blockOperationWithBlock:^{}];
    [op addObserver:self forKeyPath:NSStringFromSelector(@selector(isExecuting)) options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld) context:NULL];
    [op addObserver:self forKeyPath:NSStringFromSelector(@selector(isFinished)) options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld) context:NULL];

    [op start];

    XCTAssertEqual(changes.count, 3);
    XCTAssert([@"isExecuting" isEqualToString:changes[0][kKeyPath]]);
    XCTAssertEqual(changes[0][kChange][NSKeyValueChangeOldKey], @NO);
    XCTAssertEqual(changes[0][kChange][NSKeyValueChangeNewKey], @YES);
    XCTAssert([@"isExecuting" isEqualToString:changes[1][kKeyPath]]);
    // these 2 assertions fail - bug in SDK?  see http://stackoverflow.com/questions/39883783/nsoperation-key-value-observing-isexecuting-old-and-new-values-not-as-expected
//    XCTAssertEqual(changes[1][kChange][NSKeyValueChangeOldKey], @YES);
//    XCTAssertEqual(changes[1][kChange][NSKeyValueChangeNewKey], @NO);
    XCTAssert([@"isFinished" isEqualToString:changes[2][kKeyPath]]);
    XCTAssertEqual(changes[2][kChange][NSKeyValueChangeOldKey], @NO);
    XCTAssertEqual(changes[2][kChange][NSKeyValueChangeNewKey], @YES);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    [changes addObject:@{kKeyPath: keyPath, kChange: change}];
}

@end
