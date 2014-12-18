//
//  KMLTests.m
//  InteractiveReports
//
//  Created by Robert St. John on 12/18/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "SimpleKML.h"
#import "SimpleKMLDocument.h"

@interface KMLTests : XCTestCase

@end

@implementation KMLTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testExample {
    NSURL *kmlURL = [[NSBundle bundleForClass:self.class] URLForResource:@"mage-export" withExtension:@"kml"];
    SimpleKML *kml = [SimpleKML KMLWithContentsOfURL:kmlURL error:NULL];
    XCTAssertNotNil(kml);
    NSLog(@"kml %@ has %lu placemarks", kmlURL, (unsigned long)kml.feature.document.flattenedPlacemarks.count);
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

@end
