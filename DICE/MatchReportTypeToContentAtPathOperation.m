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
        __block NSURL *sourceFile;
        [self.report.managedObjectContext performBlockAndWait:^{
            sourceFile = self.report.sourceFile;
        }];
        [_candidates enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            id<ReportType> candidate = obj;
            // TODO: can't just use sourceFile here now that reports will move to import dir
            if ([candidate couldImportFromPath:sourceFile]) {
                _matchedReportType = candidate;
                *stop = YES;
            }
        }];
    }
}

@end
