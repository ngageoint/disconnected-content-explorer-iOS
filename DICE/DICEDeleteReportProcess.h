//
// Created by Robert St. John on 5/14/17.
// Copyright (c) 2017 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ImportProcess.h"

@class Report;


/**
 * First, move files to the specified trash directory, then schedule the files to be deleted from there.
 */
@interface DICEDeleteReportProcess : ImportProcess

@property (readonly, nonnull, nonatomic) NSURL *trashDir;
@property (readonly, nonnull, nonatomic) NSFileManager *fileManager;
/** a unique, generated sub-directory in the trash directory where the report files will move before being deleted; no KVO */
@property (readonly, nonnull, nonatomic) NSURL *trashContainerDir;
/** Delete only the source file and base directory, but leave the container import directory and any generated data it contains. */
@property (readonly, nonatomic) BOOL isPreservingMetaData;

- (nullable instancetype)initWithReport:(nonnull Report *)report trashDir:(nonnull NSURL *)trashDir preservingMetaData:(BOOL)perserveMetaData fileManager:(nonnull NSFileManager *)fileManager;

@end

@protocol DICEDeleteReportProcessDelegate <ImportDelegate>

- (void)filesDidMoveToTrashByDeleteReportProcess:(nonnull DICEDeleteReportProcess *)process;
- (void)noFilesFoundToDeleteByDeleteReportProcess:(nonnull DICEDeleteReportProcess *)process;

@end
