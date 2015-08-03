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
#import "ZipFile.h"


@interface ZippedHtmlImportProcess : BaseImportProcess <ImportProcess>

@property (readonly) NSURL *destDir;

- (instancetype)initWithReport:(Report *)report destDir:(NSURL *)destDir zipFile:(ZipFile *)zipFile;

@end


@interface ValidateHtmlLayoutOperation : NSOperation

@property (readonly) ZipFile *zipFile;
@property (readonly) BOOL isLayoutValid;
/**
 the path of the directory that contains index.html whithin the zip file;
 set after the operation finishes; can be the empty string
 */
@property (readonly) NSString *indexDirPath;

- (instancetype)initWithZipFile:(ZipFile *)zipFile;

@end


@interface HtmlReportType : NSObject <ReportType>

- (instancetype)initWithFileManager:(NSFileManager *)fileManager NS_DESIGNATED_INITIALIZER;

@end
