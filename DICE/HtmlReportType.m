//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "HtmlReportType.h"

#import "SimpleFileManager.h"
#import "FileOperations.h"
#import "UnzipOperation.h"

// objective-zip
#import "ZipFile.h"
#import "FileInZipInfo.h"


@implementation ValidateHtmlLayoutOperation

/*
 TODO: combine this with the logic of couldHandleFile: to DRY
 */

- (instancetype)initWithZipFile:(ZipFile *)zipFile
{
    self = [super init];

    if (!self) {
        return nil;
    }

    _zipFile = zipFile;

    return self;
}


- (void)main
{
    @autoreleasepool {
        NSArray *entries = [self.zipFile listFileInZipInfos];

        __block NSString *mostShallowIndexEntry = nil;
        // index.html must be at most one directory deep
        __block NSUInteger indexDepth = 2;
        __block BOOL hasNonIndexRootEntries = NO;
        NSMutableSet *baseDirs = [NSMutableSet set];

        [entries enumerateObjectsUsingBlock:^(FileInZipInfo *entry, NSUInteger index, BOOL *stop) {
            NSArray *steps = entry.name.pathComponents;
            if (steps.count > 1) {
                [baseDirs addObject:steps.firstObject];
            }
            if ([@"index.html" isEqualToString:steps.lastObject]) {
                if (steps.count == 1) {
                    mostShallowIndexEntry = entry.name;
                    indexDepth = 0;
                    *stop = YES;
                }
                else if (steps.count - 1 < indexDepth) {
                    mostShallowIndexEntry = entry.name;
                    indexDepth = steps.count - 1;
                }
            }
            else if (steps.count == 1) {
                hasNonIndexRootEntries = YES;
            }
        }];

        if (indexDepth > 0 && (hasNonIndexRootEntries || baseDirs.count > 1)) {
            mostShallowIndexEntry = nil;
        }
        
        if (mostShallowIndexEntry) {
            _indexDirPath = [mostShallowIndexEntry stringByDeletingLastPathComponent];
            _isLayoutValid = YES;
        }
    }
}

@end


@implementation ZippedHtmlImportProcess

- (instancetype)initWithReport:(Report *)report
    destDir:(NSURL *)destDir
    zipFile:(ZipFile *)zipFile
    fileManager:(id<SimpleFileManager>)fileManager
{
    ValidateHtmlLayoutOperation *validateStep = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];
    validateStep.completionBlock = ^{
        [self validateStepDidFinish];
    };

    UnzipOperation *unzipStep = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:nil];
    [unzipStep addDependency:validateStep];

    self = [super initWithReport:report steps:@[
        validateStep,
        unzipStep,
    ]];

    if (!self) {
        return nil;
    }

    _destDir = destDir;
    _fileManager = fileManager;

    return self;
}

- (void)validateStepDidFinish
{
    ValidateHtmlLayoutOperation *validateStep = self.steps.firstObject;
    UnzipOperation *unzipStep = self.steps[1];

    if (validateStep.isLayoutValid) {
        if (validateStep.indexDirPath.length == 0) {
            NSString *destDirPath = [self.report.url.lastPathComponent stringByDeletingPathExtension];
            unzipStep.destDir = [self.destDir URLByAppendingPathComponent:destDirPath];
        }
        else {
            unzipStep.destDir = self.destDir;
        }
    }
    else {
        [unzipStep cancel];
    }
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
    id<FileInfo> fileInfo = [self.fileManager infoForPath:filePath];
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
        fileInfo = [self.fileManager infoForPath:indexPath];
        return fileInfo && fileInfo.isRegularFile;
    }

    return NO;
}


- (id<ImportProcess>)createImportProcessForReport:(Report *)report
{
    ZipFile *zipFile = [[ZipFile alloc] initWithFileName:report.url.path mode:ZipFileModeUnzip];
    ZippedHtmlImportProcess *process = [[ZippedHtmlImportProcess alloc] initWithReport:report
        destDir:nil zipFile:zipFile fileManager:self.fileManager];

    return process;
}

@end
