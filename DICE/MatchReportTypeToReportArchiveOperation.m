//
// Created by Robert St. John on 8/23/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "MatchReportTypeToReportArchiveOperation.h"
#import "Report.h"
#import "DICEArchive.h"
#import "ReportType.h"
#import "DICEUtiExpert.h"


@implementation MatchReportTypeToReportArchiveOperation {
    DICEUtiExpert *_utiExpert;
}

- (instancetype)initWithReport:(Report *)report reportArchive:(id<DICEArchive>)archive candidateTypes:(NSArray<id<ReportType>> *)types utiExpert:(DICEUtiExpert *)utiExpert
{
    if (!(self = [super init])) {
        return nil;
    }

    _report = report;
    _reportArchive = archive;
    _candidates = types;
    _utiExpert = utiExpert;

    return self;
}


- (void)main
{
    @autoreleasepool {
        NSMutableArray *predicates = [NSMutableArray arrayWithCapacity:self.candidates.count];
        for (id<ReportType> candidate in self.candidates) {
            [predicates addObject:[candidate createContentMatchingPredicate]];
        }
        [self.reportArchive enumerateEntriesUsingBlock:^(id<DICEArchiveEntry> entry) {
            CFStringRef uti = [_utiExpert probableUtiForPathName:[entry archiveEntryPath] conformingToUti:NULL];
            for (id<ReportTypeMatchPredicate> predicate in predicates) {
                [predicate considerContentWithName:entry.archiveEntryPath probableUti:uti];
            }
        }];
        for (id<ReportTypeMatchPredicate> predicate in predicates) {
            if (predicate.contentCouldMatch) {
                _matchedReportType = predicate.reportType;
                return;
            }
        }
    }

}

@end