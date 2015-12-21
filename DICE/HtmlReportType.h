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

- (instancetype)initWithFileManager:(NSFileManager *)fileManager NS_DESIGNATED_INITIALIZER;

@end

