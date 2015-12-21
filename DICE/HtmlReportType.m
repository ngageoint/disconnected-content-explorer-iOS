//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "HtmlReportType.h"

#import "ZippedHtmlImportProcess.h"
#import "ZipFile.h"




@interface HtmlReportType ()

@property (strong, nonatomic, readonly) NSFileManager *fileManager;

@end




@implementation HtmlReportType

- (instancetype)initWithFileManager:(NSFileManager *)fileManager
{
    self = [super init];

    if (!self) {
        return nil;
    }

    _fileManager = fileManager;

    return self;
}

- (instancetype)init
{
    return [self initWithFileManager:[NSFileManager defaultManager]];
}

- (BOOL)couldHandleFile:(NSURL *)filePath
{
    NSDictionary *attrs = [self.fileManager attributesOfItemAtPath:filePath.path error:nil];
    NSString *fileType = attrs.fileType;

    if ([NSFileTypeRegular isEqualToString:fileType])
    {
        NSString *ext = [filePath.pathExtension lowercaseString];
        return
            [@"zip" isEqualToString:ext] ||
            [@"html" isEqualToString:ext];
    }
    else if ([NSFileTypeDirectory isEqualToString:fileType])
    {
        NSURL *indexPath = [filePath URLByAppendingPathComponent:@"index.html"];
        attrs = [self.fileManager attributesOfItemAtPath:indexPath.path error:nil];
        return attrs && [NSFileTypeRegular isEqualToString:attrs.fileType];
    }

    return NO;
}

- (id<ImportProcess>)createProcessToImportReport:(Report *)report toDir:(NSURL *)destDir
{
    ZipFile *zipFile = [[ZipFile alloc] initWithFileName:report.url.path mode:ZipFileModeUnzip];
    ZippedHtmlImportProcess *process = [[ZippedHtmlImportProcess alloc] initWithReport:report
        destDir:destDir zipFile:zipFile fileManager:self.fileManager];

    return process;
}

@end
