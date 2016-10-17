//
// Created by Robert St. John on 9/13/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <geopackage-ios/GPKGColumnValues.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "DICEDefaultArchiveFactory.h"
#import "DICEUtiExpert.h"
#import "DICEOZZipFileArchive.h"


@implementation DICEDefaultArchiveFactory {
    DICEUtiExpert *_utiExpert;
}

- (instancetype)initWithUtiExpert:(DICEUtiExpert *)utiExpert
{
    if (!(self = [super init])) {
        return nil;
    }

    _utiExpert = utiExpert;

    return self;
}

- (id<DICEArchive>)createArchiveForResource:(NSURL *)archiveResource withUti:(CFStringRef)archiveResourceUti
{
    if (!archiveResourceUti) {
        archiveResourceUti = [_utiExpert probableUtiForPathName:archiveResource.path conformingToUti:nil];
    }
    if (![_utiExpert uti:archiveResourceUti conformsToUti:kUTTypeZipArchive]) {
        return nil;
    }
    return [[DICEOZZipFileArchive alloc] initWithArchivePath:archiveResource archiveUti:archiveResourceUti];
}

@end