//
// Created by Robert St. John on 8/26/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Report;
@protocol ReportType;


@interface MatchReportTypeToContentAtPathOperation : NSOperation

@property (readonly, nonnull) Report *report;
@property (readonly, nullable) id<ReportType> matchedReportType;

- (nullable instancetype)initWithReport:(nonnull Report *)report candidateTypes:(nonnull NSArray<id<ReportType>> *)candidates;

@end