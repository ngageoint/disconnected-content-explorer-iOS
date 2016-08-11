//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <objective-zip/Objective-Zip.h>
#import "HtmlReportType.h"
#import "UnzipOperation.h"
#import "ZippedHtmlImportProcess.h"
#import "ExplodedHtmlImportProcess.h"


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

- (BOOL)couldImportFile:(NSURL *)filePath
{
    NSDictionary *attrs = [self.fileManager attributesOfItemAtPath:filePath.path error:nil];

    return [self isZipFile:filePath attributes:attrs] ||
        [self isHtmlFile:filePath attributes:attrs] ||
        [self isHtmlBaseDir:filePath attributes:attrs];
}

- (ImportProcess *)createProcessToImportReport:(Report *)report toDir:(NSURL *)destDir
{
    NSDictionary *fileAttrs = [self.fileManager attributesOfItemAtPath:report.url.path error:nil];
    if ([self isZipFile:report.url attributes:fileAttrs]) {
        OZZipFile *zipFile = [[OZZipFile alloc] initWithFileName:report.url.path mode:OZZipFileModeUnzip];
        ZippedHtmlImportProcess *process = [[ZippedHtmlImportProcess alloc] initWithReport:report
            destDir:destDir zipFile:zipFile fileManager:self.fileManager];
        return process;
    }
    else if ([self isHtmlBaseDir:report.url attributes:fileAttrs]) {
        ExplodedHtmlImportProcess *process = [[ExplodedHtmlImportProcess alloc]
            initWithReport:report fileManager:self.fileManager];
        return process;
    }
    else if ([self isHtmlFile:report.url attributes:fileAttrs]) {
        ExplodedHtmlImportProcess *process = [[ExplodedHtmlImportProcess alloc]
            initWithReport:report fileManager:self.fileManager];
        return process;
    }
    return nil;
}

- (BOOL)isZipFile:(NSURL *)filePath attributes:(NSDictionary *)fileAttrs
{
    NSString *fileType = fileAttrs[NSFileType];
    if ([NSFileTypeRegular isEqualToString:fileType]) {
        NSString *ext = filePath.pathExtension.lowercaseString;
        return [@"zip" isEqualToString:ext];
    }
    return NO;
}

- (BOOL)isHtmlBaseDir:(NSURL *)filePath attributes:(NSDictionary *)fileAttrs
{
    NSString *fileType = fileAttrs[NSFileType];
    if ([NSFileTypeDirectory isEqualToString:fileType]) {
        NSURL *indexPath = [filePath URLByAppendingPathComponent:@"index.html"];
        fileAttrs = [self.fileManager attributesOfItemAtPath:indexPath.path error:nil];
        return fileAttrs && [NSFileTypeRegular isEqualToString:fileAttrs.fileType];
    }
    return NO;
}

- (BOOL)isHtmlFile:(NSURL *)filePath attributes:(NSDictionary *)fileAttrs
{
    NSString *ext = filePath.pathExtension.lowercaseString;
    if ([NSFileTypeRegular isEqualToString:fileAttrs[NSFileType]]) {
        return [@"html" isEqualToString:ext];
    }
    return NO;
}

@end
