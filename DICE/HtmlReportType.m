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
#import "ParseJsonOperation.h"

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
            else {
                if ([@"metadata.json" isEqualToString:steps.lastObject]) {
                    _metaDataPath = entry.name;
                }
                if (steps.count == 1) {
                    hasNonIndexRootEntries = YES;
                }
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
    ValidateHtmlLayoutOperation *validation = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

    MkdirOperation *makeDestDir = [[MkdirOperation alloc] init];
    [makeDestDir addDependency:validation];

    UnzipOperation *unzip = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:nil];
    [unzip addDependency:makeDestDir];

    ParseJsonOperation *parseMetaData = [[ParseJsonOperation alloc] init];
    [parseMetaData addDependency:unzip];

//    DeleteFileOperation *deleteZip = [[DeleteFileOperation alloc] initWithFileUrl:report.url];
//    [deleteZip addDependency:parseMetaData];

    self = [super initWithReport:report steps:@[
        validation,
        makeDestDir,
        unzip,
        parseMetaData,
    ]];

    if (!self) {
        return nil;
    }

    __weak ZippedHtmlImportProcess *weakSelf = self;
    validation.completionBlock = ^{
        [weakSelf validateStepDidFinish];
    };
    makeDestDir.completionBlock = ^{
        [weakSelf makeDestDirStepDidFinish];
    };

    _destDir = destDir;
    _fileManager = fileManager;

    return self;
}

- (void)validateStepDidFinish
{
    ValidateHtmlLayoutOperation *validateStep = self.steps.firstObject;
    MkdirOperation *makeDestDirStep = self.steps[1];

    if (!validateStep.isLayoutValid) {
        [self cancelRemainingSteps];
        return;
    }

    NSURL *destDir = self.destDir;
    if (validateStep.indexDirPath.length == 0) {
        NSString *destDirPath = [self.report.url.lastPathComponent stringByDeletingPathExtension];
        destDir = [self.destDir URLByAppendingPathComponent:destDirPath isDirectory:YES];
    }
    makeDestDirStep.dirUrl = destDir;
}

- (void)makeDestDirStepDidFinish
{
    MkdirOperation *makeDestDirStep = self.steps[1];

    if (!(makeDestDirStep.dirWasCreated || makeDestDirStep.dirExisted)) {
        [self cancelRemainingSteps];
        return;
    }

    UnzipOperation *unzipStep = self.steps[2];
    unzipStep.destDir = makeDestDirStep.dirUrl;
}

- (void)unzipStepDidFinish
{

}

- (void)parseMetaDataStepDidFinish
{
    ParseJsonOperation *parseMetaData = self.steps[3];
    // TODO: update report on main thread
    [self.report setPropertiesFromJsonDescriptor:parseMetaData.parsedJsonDictionary];
}

- (void)cancelRemainingSteps
{
    for (NSOperation *step in self.steps) {
        if (!step.finished) {
            [step cancel];
        }
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
