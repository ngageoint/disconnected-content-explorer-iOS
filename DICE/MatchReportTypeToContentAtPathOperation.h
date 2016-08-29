//
// Created by Robert St. John on 8/26/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Report;
@protocol ReportType;


@interface MatchReportTypeToContentAtPathOperation : NSObject

@property (readonly) id<ReportType> matchedReportType;

- (instancetype)initWithReport:(Report *) candidateTypes:(NSArray<id<ReportType>> *)candidates;

@end