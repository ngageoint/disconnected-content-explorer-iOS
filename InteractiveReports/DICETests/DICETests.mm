//
//  DICETests.m
//  DICETests
//
//  Created by Robert St. John on 11/21/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "ReportAPI.h"
#import "Planet.hpp"
#import "Factory_iOS.hpp"
#import "JSONParser_iOS.hpp"
#import "Logger_iOS.hpp"
#import "MathUtils_iOS.hpp"
#import "StringBuilder_iOS.hpp"
#import "StringUtils_iOS.hpp"
#import "TextUtils_iOS.hpp"

@interface DICETests : XCTestCase

@end

@implementation DICETests

- (void)setUp {
    [super setUp];
    
    // setup the g3m environment
    ILogger::setInstance(new Logger_iOS(InfoLevel));
    IFactory::setInstance(new Factory_iOS());
    IStringUtils::setInstance(new StringUtils_iOS());
    IStringBuilder::setInstance(new StringBuilder_iOS());
    IMathUtils::setInstance(new MathUtils_iOS());
    IJSONParser::setInstance(new JSONParser_iOS());
    ITextUtils::setInstance(new TextUtils_iOS());
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

@end
