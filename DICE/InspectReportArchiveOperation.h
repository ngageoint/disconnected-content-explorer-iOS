//
// Created by Robert St. John on 8/23/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DICEArchive.h"

@class Report;
@class DICEUtiExpert;
@protocol DICEArchive;
@protocol ReportType;
@protocol ReportTypeMatchPredicate;


@interface InspectReportArchiveOperation : NSOperation

@property (readonly) Report *report;
@property (readonly) id<DICEArchive> reportArchive;
@property (readonly) NSArray<id<ReportType>> *candidates;
/**
 * TODO: This was changed from being the matching ReportType instance to the ReportTypeMatchPredicate
 * that was used to evalute the content entries with the intent that the predicate could pass information
 * down the chain to the import process so that it would not have to redundantly inspect the extracted
 * archive contents.  This might not be necessary but the thought is captured here nonetheless.
 */
@property (readonly) id<ReportTypeMatchPredicate> matchedPredicate;
@property (readonly) uint64_t totalExtractedSize;
@property (readonly) NSString *archiveBaseDir;

- (instancetype)initWithReport:(Report *)report reportArchive:(id<DICEArchive>)archive candidateReportTypes:(NSArray<id<ReportType>> *)types utiExpert:(DICEUtiExpert *)utiExpert;

@end
