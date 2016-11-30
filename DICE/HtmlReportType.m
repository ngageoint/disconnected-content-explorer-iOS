//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "HtmlReportType.h"
#import "UnzipOperation.h"
#import "ExplodedHtmlImportProcess.h"
#import "Report.h"


@interface HtmlReportType ()

@property (strong, nonatomic, readonly) NSFileManager *fileManager;

@end


@interface HtmlReportTypeMatchPredicate : NSObject <ReportTypeMatchPredicate>

@property (readonly) id<ReportType> reportType;
@property (readonly) BOOL contentCouldMatch;

@end


@implementation HtmlReportTypeMatchPredicate {
    NSArray *_indexEntry;
    ContentEnumerationInfo *_contentInfo;
}

- (instancetype)initWithReportType:(HtmlReportType *)reportType
{
    if (!(self = [super init])) {
        return nil;
    }

    _reportType = reportType;

    return self;
}

- (void)considerContentEntryWithName:(NSString *)name probableUti:(CFStringRef)uti contentInfo:(ContentEnumerationInfo *)info
{
    _contentInfo = info;
    NSArray<NSString *> *nameParts = name.pathComponents;
    NSString *baseName = nameParts.lastObject;
    if ([@"index.html" isEqualToString:baseName] && nameParts.count <= 2) {
        if (_indexEntry == nil || nameParts.count < _indexEntry.count) {
            _indexEntry = nameParts;
        }
    }
}

- (BOOL)contentCouldMatch
{
    if (!_indexEntry) {
        return NO;
    }
    if (!_contentInfo.hasBaseDir) {
        // index in the root
        return _indexEntry.count == 1;
    }
    if (_contentInfo.entryCount < 2) {
        // only one entry - index.html
        return _indexEntry.count <= 2;
    }
    // index.html in a base dir
    return _indexEntry.count == 2;
}

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

- (BOOL)couldImportFromPath:(NSURL *)filePath
{
    NSDictionary *attrs = [self.fileManager attributesOfItemAtPath:filePath.path error:nil];

    return
        [self isHtmlFile:filePath attributes:attrs] ||
        [self isHtmlBaseDir:filePath attributes:attrs];
}

- (id<ReportTypeMatchPredicate>)createContentMatchingPredicate
{
    return [[HtmlReportTypeMatchPredicate alloc] initWithReportType:self];
}

- (ImportProcess *)createProcessToImportReport:(Report *)report toDir:(NSURL *)destDir
{
    NSDictionary *attrs = [self.fileManager attributesOfItemAtPath:report.rootResource.path error:nil];
    if ([self isHtmlBaseDir:report.rootResource attributes:attrs]) {
        return [[ExplodedHtmlImportProcess alloc] initWithReport:report];
    }
    else if ([self isHtmlFile:report.rootResource attributes:attrs]) {
        return [[NoopImportProcess alloc] initWithReport:report];
    }
    return nil;
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
