//
// Created by Robert St. John on 9/12/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DICEArchive.h"



@interface TestDICEArchive : NSObject <DICEArchive>

+ (instancetype)archiveWithEntries:(NSArray<id<DICEArchiveEntry>> *)entries archiveUrl:(NSURL *)url archiveUti:(CFStringRef)uti;

@end


@interface TestDICEArchiveEntry : NSObject <DICEArchiveEntry>

+ (instancetype)entryWithName:(NSString *)name sizeInArchive:(archive_size_t)inArchive sizeExtracted:(archive_size_t)extracted;

@end
