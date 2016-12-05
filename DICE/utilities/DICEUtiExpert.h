//
// Created by Robert St. John on 8/24/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface DICEUtiExpert : NSObject

// TODO: these returned CFStringRef values might actually never be null as the UTType functions supposedly always return dynamic utis if one cannot be deteremined
- (nullable CFStringRef)preferredUtiForExtension:(nonnull NSString *)ext conformingToUti:(nullable CFStringRef)constraint;
- (nullable CFStringRef)preferredUtiForMimeType:(nonnull NSString *)type conformingToUti:(nullable CFStringRef)uti;
- (nullable CFStringRef)probableUtiForPathName:(nonnull NSString *)pathName conformingToUti:(nullable CFStringRef)constraint;
- (nullable CFStringRef)probableUtiForResource:(nonnull NSURL *)resource conformingToUti:(nullable CFStringRef)constraint;
- (BOOL)uti:(nonnull CFStringRef)testUti isEqualToUti:(nonnull CFStringRef)basisUti;
- (BOOL)uti:(nonnull CFStringRef)testUti conformsToUti:(nonnull CFStringRef)basisUti;
- (BOOL)isDynamicUti:(nonnull CFStringRef)uti;

@end