//
// Created by Robert St. John on 8/22/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DICEArchive.h"
#import <objective-zip/Objective-Zip.h>


@interface DICEOZZipFileArchive : OZZipFile <DICEArchive>

- (instancetype)initWithArchivePath:(NSURL *)path utType:(CFStringRef)utType;

@end