//
//  NSURL+ResourceValues.m
//  DICE
//
//  Created by Robert St. John on 6/16/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "NSURL+ResourceValues.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface NSURLResourceValuesTest : XCTestCase

@end

@implementation NSURLResourceValuesTest
{
    NSBundle *bundle;
    NSURL *bundleDir;
    NSURL *zipFile;
}



- (void)setUp {
    [super setUp];

    bundle = [NSBundle bundleForClass:[self class]];
    bundleDir = bundle.bundleURL;
    zipFile = [bundle URLForResource:@"single_entry" withExtension:@"zip" subdirectory:@"etc"];
}

- (void)tearDown {
    [super tearDown];
}

- (void)testIsDirectory
{
    NSURLFileResourceType val;
    [zipFile getResourceValue:&val forKey:NSURLFileResourceTypeKey error:NULL];
    XCTAssertEqualObjects(val, NSURLFileResourceTypeRegular);
    
    XCTAssertTrue(bundleDir.isDirectory.boolValue);
    XCTAssertFalse(zipFile.isDirectory.boolValue);
}

- (void)testTypeIdentifier
{
    XCTAssertEqualObjects(bundleDir.typeIdentifier, (__bridge NSString *)kUTTypeFolder);
    XCTAssertEqualObjects(zipFile.typeIdentifier, (__bridge NSString *)kUTTypeZipArchive);
}

@end
