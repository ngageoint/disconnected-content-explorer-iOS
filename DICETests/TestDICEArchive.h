//
// Created by Robert St. John on 9/12/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DICEArchive.h"



@interface TestDICEArchive : NSObject <DICEArchive>

+ (instancetype)archiveWithEntries:(NSArray<id<DICEArchiveEntry>> *)entries archiveUrl:(NSURL *)url archiveUti:(CFStringRef)uti;

/** enqueue to the end, dequeue from the start */
@property NSMutableArray<NSError *> *errorQueue;

- (void)enqueueError:(NSError *)error;
- (NSError *)dequeuError;

@end


@interface TestDICEArchiveEntry : NSObject <DICEArchiveEntry>

+ (instancetype)entryWithName:(NSString *)name sizeInArchive:(uint64_t)inArchive sizeExtracted:(uint64_t)extracted;

@end
