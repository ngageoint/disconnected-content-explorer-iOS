//
//  HtmlReport.h
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ReportType.h"

@interface HtmlReportType : NSObject <ReportType>

- (instancetype)initWithFileManager:(NSFileManager *)fileManager workQueue:(NSOperationQueue *)workQueue NS_DESIGNATED_INITIALIZER;

- (BOOL)couldHandleFile:(NSURL *)filePath;

@end
