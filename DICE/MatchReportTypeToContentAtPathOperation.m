//
// Created by Robert St. John on 8/26/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "MatchReportTypeToContentAtPathOperation.h"
#import "Report.h"
#import "ReportType.h"


@implementation MatchReportTypeToContentAtPathOperation {
    NSArray *_candidates;
}

- (instancetype)initWithReport:(Report *)report candidateTypes:(NSArray<id<ReportType>> *)candidates
{
    if (!(self = [super init])) {
        return nil;
    }

    _report = report;
    _candidates = candidates;

    return self;
}

- (void)main
{
    @autoreleasepool {
        [_candidates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            id<ReportType> candidate = obj;
            if ([candidate couldImportFromPath:self.report.rootResource]) {
                _matchedReportType = candidate;
                *stop = YES;
            }
        }];
    }
}

@end