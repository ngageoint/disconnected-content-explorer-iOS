//
//  ResourceTypesTests.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/21/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "ResourceTypes.h"

@interface ResourceTypesTests : XCTestCase

@end

@implementation ResourceTypesTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testCanOpenZipResource {
    NSURL *resource = [NSURL URLWithString:@"file:///resources/resource.zip"];
    XCTAssert([ResourceTypes canOpenResource:resource], @"could not open zip resource");
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

@end
