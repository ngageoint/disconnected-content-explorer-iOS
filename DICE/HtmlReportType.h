//
//  HtmlReport.h
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ReportType.h"
#import "BaseImportProcess.h"


@interface ZippedHtmlImportProcess : BaseImportProcess <ImportProcess>

@property (nonatomic, readonly) NSURL *destDir;

- (instancetype)initWithReport:(Report *)report destDir:(NSURL *)destDir;

@end


@interface ValidateHtmlLayoutOperation : NSOperation

- (instancetype)initWithFile:(NSURL *)file;

@end


@interface HtmlReportType : NSObject <ReportType>

- (instancetype)initWithFileManager:(NSFileManager *)fileManager NS_DESIGNATED_INITIALIZER;

@end
