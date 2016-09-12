//
// Created by Robert St. John on 8/24/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface DICEUtiExpert : NSObject

- (nullable CFStringRef)preferredUtiForExtension:(nonnull NSString *)ext conformingToUti:(nullable CFStringRef)constraint;
- (nullable CFStringRef)probableUtiForPathName:(nonnull NSString *)pathName conformingToUti:(nullable CFStringRef)constraint;
- (BOOL)uti:(nonnull CFStringRef)testUti isEqualToUti:(nonnull CFStringRef)basisUti;
- (BOOL)uti:(nonnull CFStringRef)testUti conformsToUti:(nonnull CFStringRef)basisUti;

@end