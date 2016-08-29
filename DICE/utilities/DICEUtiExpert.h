//
// Created by Robert St. John on 8/24/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface DICEUtiExpert : NSObject

- (CFStringRef)preferredUtiForExtension:(NSString *)ext conformingToUti:(nullable CFStringRef)constraint;
- (CFStringRef)probableUtiForPathName:(NSString *)pathName conformingToUti:(nullable CFStringRef)constraint;
- (BOOL)uti:(CFStringRef)testUti isEqualToUti:(CFStringRef)basisUti;
- (BOOL)uti:(CFStringRef)testUti conformsToUti:(CFStringRef)basisUti;

@end