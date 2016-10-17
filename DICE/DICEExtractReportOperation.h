//
// Created by Robert St. John on 9/21/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "UnzipOperation.h"

@class Report;
@protocol ReportType;


@interface DICEExtractReportOperation : UnzipOperation

@property (readonly) Report *report;
@property (readonly) id<ReportType> reportType;
@property (readonly) NSURL *extractedReportBaseDir;

- (instancetype)initWithReport:(Report *)report reportType:(id<ReportType>)reportType extractedBaseDir:(NSURL *)baseDir archive:(id<DICEArchive>)archive extractToDir:(NSURL *)destDir fileManager:(NSFileManager *)fileManager;

@end