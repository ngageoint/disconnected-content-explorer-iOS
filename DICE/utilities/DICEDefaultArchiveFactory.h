//
// Created by Robert St. John on 9/13/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DICEArchive.h"

@class DICEUtiExpert;


@interface DICEDefaultArchiveFactory : NSObject <DICEArchiveFactory>

- (instancetype)initWithUtiExpert:(DICEUtiExpert *)utiExpert;

@end