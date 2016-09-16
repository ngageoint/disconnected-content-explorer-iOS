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
    _totalExtractedSize = 0;

    return self;
}


- (void)main
{
    @autoreleasepool {
        NSMutableArray *predicates = [NSMutableArray arrayWithCapacity:self.candidates.count];
        for (id<ReportType> candidate in self.candidates) {
            [predicates addObject:[candidate createContentMatchingPredicate]];
        }
        [self.reportArchive enumerateEntriesUsingBlock:^void(id<DICEArchiveEntry> entry) {
            _totalExtractedSize += [entry archiveEntrySizeExtracted];
            [self checkForBaseDirFromEntry:entry];
            CFStringRef uti = [_utiExpert probableUtiForPathName:[entry archiveEntryPath] conformingToUti:NULL];
            for (id<ReportTypeMatchPredicate> predicate in predicates) {
                [predicate considerContentWithName:entry.archiveEntryPath probableUti:uti];
            }
        } error:NULL];
        for (id<ReportTypeMatchPredicate> predicate in predicates) {
            if (predicate.contentCouldMatch) {
                _matchedReportType = predicate.reportType;
                return;
            }
        }
    }
}

- (void)checkForBaseDirFromEntry:(id<DICEArchiveEntry>)entry
{
    if (self.archiveBaseDir && self.archiveBaseDir.length == 0) {
        return;
    }
    NSString *entryRoot = @"";
    NSArray *pathParts = entry.archiveEntryPath.pathComponents;
    if (pathParts.count > 1 || (pathParts.count == 1 && [entry.archiveEntryPath hasSuffix:@"/"])) {
        entryRoot = pathParts.firstObject;
    }
    if (self.archiveBaseDir == nil) {
        _archiveBaseDir = entryRoot;
    }
    else if (![self.archiveBaseDir isEqualToString:entryRoot]) {
        _archiveBaseDir = @"";
    }
}

@end