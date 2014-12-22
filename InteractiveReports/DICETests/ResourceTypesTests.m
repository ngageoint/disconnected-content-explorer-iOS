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

- (void)testCanOpenLasResource {
    NSURL *resource = [NSURL URLWithString:@"file:///resources/resource.las"];
    XCTAssert([ResourceTypes canOpenResource:resource], @"could not open las resource");
}

- (void)testCanOpenLasZipResource {
    NSURL *resource = [NSURL URLWithString:@"file:///resources/resource.laz"];
    XCTAssert([ResourceTypes canOpenResource:resource]);
}

- (void)testCanOpenZipResource {
    NSURL *resource = [NSURL URLWithString:@"file:///resources/resource.zip"];
    XCTAssert([ResourceTypes canOpenResource:resource], @"could not open zip resource");
}

- (void)testCanOpenGlob3Pointcloud {
    NSURL *resource = [NSURL URLWithString:@"file:///resources/resource.g3m-pointcloud"];
    XCTAssert([ResourceTypes canOpenResource:resource], @"could not open glob3 pointcloud resource");
}

- (void)testCanOpenKML {
    NSURL *resource = [NSURL URLWithString:@"file:///resources/resource.kml"];
    XCTAssert([ResourceTypes canOpenResource:resource], @"could not open kml resource");
    
    resource = [NSURL URLWithString:@"file:///resources/resource.kmz"];
    XCTAssert([ResourceTypes canOpenResource:resource], @"could not open kmz resource");
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

@end
