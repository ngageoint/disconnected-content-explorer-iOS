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


@interface HtmlReportType ()

@property (strong, nonatomic, readonly) NSFileManager *fileManager;

@end


@interface HtmlReportTypeMatchPredicate : NSObject <ReportTypeMatchPredicate>

@property (readonly) id<ReportType> reportType;
@property (readonly) BOOL contentCouldMatch;

@end


@implementation HtmlReportTypeMatchPredicate {
    NSString *_baseDir;
    NSArray *_indexEntry;
    NSMutableSet *_rootEntries;
}

- (instancetype)initWithReportType:(HtmlReportType *)reportType
{
    _reportType = reportType;
    _rootEntries = [NSMutableSet set];
}

- (void)considerContentWithName:(NSString *)name probableUti:(CFStringRef)uti
{
    NSArray<NSString *> *nameParts = name.pathComponents;
    NSString *entryRoot = nameParts.firstObject;
    if ([entryRoot hasSuffix:@"/"]) {
        if (_baseDir == nil) {
            _baseDir = entryRoot;
        }
        else if (![entryRoot isEqualToString:_baseDir]) {
            _baseDir = @"";
        }
    }

    if (nameParts.count == 1) {
        [_rootEntries addObject:name];
    }

    NSString *baseName = nameParts.lastObject;
    if ([@"index.html" isEqualToString:baseName] && nameParts.count <= 2) {
        if (_indexEntry == nil) {
            _indexEntry = nameParts;
        }
        else if (nameParts.count < _indexEntry.count) {
            _indexEntry = nameParts;
        }
        else if (nameParts.count == _indexEntry.count) {
            // hmm - oh well
        }
    }
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

}

- (ImportProcess *)createProcessToImportReport:(Report *)report toDir:(NSURL *)destDir
{
    ExplodedHtmlImportProcess *process = [[ExplodedHtmlImportProcess alloc]
        initWithReport:report fileManager:self.fileManager];
    return process;
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
