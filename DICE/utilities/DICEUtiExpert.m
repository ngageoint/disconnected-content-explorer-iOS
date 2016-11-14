//
// Created by Robert St. John on 8/24/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import "DICEUtiExpert.h"


@implementation DICEUtiExpert {
}

- (CFStringRef)preferredUtiForExtension:(NSString *)ext conformingToUti:(nullable CFStringRef)constraint
{
    return UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)ext, constraint);
}

- (CFStringRef)probableUtiForPathName:(NSString *)pathName conformingToUti:(nullable CFStringRef)constraint
{
    if ([pathName hasSuffix:@"/"]) {
        return kUTTypeDirectory;
    }
    return [self preferredUtiForExtension:pathName.pathExtension conformingToUti:constraint];
}

- (BOOL)uti:(CFStringRef)testUti isEqualToUti:(CFStringRef)basisUti
{
    return UTTypeEqual(testUti, basisUti);
}

- (BOOL)uti:(CFStringRef)testUti conformsToUti:(CFStringRef)basisUti
{
    return UTTypeConformsTo(testUti, basisUti);
}

@end
