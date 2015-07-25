//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "HtmlReportType.h"

#import "SimpleFileManager.h"
#import "UnzipOperation.h"


@implementation ValidateHtmlLayoutOperation

/*
 TODO: combine this with the logic of couldHandleFile: to DRY
 */

- (void)main
{
    @autoreleasepool {

    }
}

@end


@implementation ZippedHtmlImportProcess

- (instancetype)initWithReport:(Report *)report destDir:(NSURL *)destDir
{
    self = [super initWithReport:report];

    if (!self) {
        return nil;
    }

    _destDir = destDir;

    [self.steps addObject:[[UnzipOperation alloc] initWithZipFile:report.url destDir:destDir]];

    return self;
}

@end


@interface HtmlReportType ()

@property (strong, nonatomic, readonly) id<SimpleFileManager> fileManager;

@end


@implementation HtmlReportType

- (HtmlReportType *)initWithFileManager:(id<SimpleFileManager>)fileManager
{
    self = [super init];

    if (!self) {
        return nil;
    }

    _fileManager = fileManager;

    return self;
}


- (BOOL)couldHandleFile:(NSURL *)filePath
{
    id<FileInfo> fileInfo = [_fileManager infoForPath:filePath];
    if (fileInfo.isRegularFile)
    {
        NSString *ext = [filePath.pathExtension lowercaseString];
        return
            [@"zip" isEqualToString:ext] ||
            [@"html" isEqualToString:ext];
    }
    else if (fileInfo.isDirectory)
    {
        NSURL *indexPath = [filePath URLByAppendingPathComponent:@"index.html"];
        fileInfo = [_fileManager infoForPath:indexPath];
        return fileInfo && fileInfo.isRegularFile;
    }

    return NO;
}


- (id<ImportProcess>)createImportProcessForReport:(Report *)report
{
    NSURL *tempDir = [_fileManager createTempDir];
    return [[ZippedHtmlImportProcess alloc] initWithReport:report destDir:tempDir];
}

@end
