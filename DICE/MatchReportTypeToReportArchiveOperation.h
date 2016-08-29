//
// Created by Robert St. John on 8/23/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Report;
@class DICEUtiExpert;
@protocol ReportType;
@protocol DICEArchive;


@interface MatchReportTypeToReportArchiveOperation : NSOperation

@property (readonly) Report *report;
@property (readonly) id<DICEArchive> reportArchive;
@property (readonly) NSArray<id<ReportType>> *candidates;
@property (readonly) id<ReportType> matchedReportType;

- (instancetype)initWithReport:(Report *)report reportArchive:(id<DICEArchive>)archive candidateTypes:(NSArray<id<ReportType>> *)types utiExpert:(DICEUtiExpert *)utiExpert;

@end