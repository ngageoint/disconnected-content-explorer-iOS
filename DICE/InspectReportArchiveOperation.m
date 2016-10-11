//
// Created by Robert St. John on 8/23/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>
#import "InspectReportArchiveOperation.h"
#import "Report.h"
#import "DICEArchive.h"
#import "ReportType.h"
#import "DICEUtiExpert.h"


@implementation InspectReportArchiveOperation {
    DICEUtiExpert *_utiExpert;
    NSMutableArray<id<ReportTypeMatchPredicate>> *_predicates;
    ContentEnumerationInfo *_contentInfo;
}

- (instancetype)initWithReport:(Report *)report reportArchive:(id<DICEArchive>)archive candidateReportTypes:(NSArray<id<ReportType>> *)types utiExpert:(DICEUtiExpert *)utiExpert
{
    if (!(self = [super init])) {
        return nil;
    }

    _report = report;
    _reportArchive = archive;
    _candidates = types;
    _utiExpert = utiExpert;
    _predicates = [NSMutableArray arrayWithCapacity:_candidates.count];
    _contentInfo = [[ContentEnumerationInfo alloc] init];

    return self;
}

- (NSString *)archiveBaseDir
{
    if (_contentInfo.hasBaseDir) {
        return _contentInfo.baseDir;
    }
    return nil;
}

- (uint64_t)totalExtractedSize
{
    return _contentInfo.totalContentSize;
}

- (void)main
{
    @autoreleasepool {
        for (id<ReportType> candidate in self.candidates) {
            [_predicates addObject:[candidate createContentMatchingPredicate]];
        }
        [self.reportArchive enumerateEntriesUsingBlock:^void(id<DICEArchiveEntry> entry) {
            [_contentInfo addInfoForEntryPath:entry.archiveEntryPath size:entry.archiveEntrySizeExtracted];
            CFStringRef uti = [_utiExpert probableUtiForPathName:[entry archiveEntryPath] conformingToUti:NULL];
            for (id<ReportTypeMatchPredicate> predicate in _predicates) {
                [predicate considerContentEntryWithName:entry.archiveEntryPath probableUti:uti contentInfo:_contentInfo];
            }
        } error:NULL];
        for (id<ReportTypeMatchPredicate> predicate in _predicates) {
            if (predicate.contentCouldMatch) {
                _matchedReportType = predicate;
                return;
            }
        }
    }
}

@end
