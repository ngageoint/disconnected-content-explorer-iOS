//
// Created by Robert St. John on 9/21/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "DICEExtractReportOperation.h"
#import "Report.h"
#import "ReportType.h"


@implementation DICEExtractReportOperation {

}

- (instancetype)initWithReport:(Report *)report reportType:(id<ReportType>)reportType extractedBaseDir:(NSURL *)baseDir archive:(id<DICEArchive>)archive extractToDir:(NSURL *)destDir fileManager:(NSFileManager *)fileManager
{
    self = [super initWithArchive:archive destDir:destDir fileManager:fileManager];

    _report = report;
    _reportType = reportType;
    _extractedReportBaseDir = baseDir;

    return self;
}

@end