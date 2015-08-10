//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "HtmlReportType.h"

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

- (BOOL)hasDescriptor
{
    return _descriptorPath != nil;
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
                }
                else if (steps.count - 1 < indexDepth) {
                    mostShallowIndexEntry = entry.name;
                    indexDepth = steps.count - 1;
                }
            }
            else {
                if ([@"metadata.json" isEqualToString:steps.lastObject]) {
                    _descriptorPath = entry.name;
                }
                if (steps.count == 1) {
                    hasNonIndexRootEntries = YES;
                }
            }
        }];

        if (indexDepth > 0 && (hasNonIndexRootEntries || baseDirs.count > 1)) {
            mostShallowIndexEntry = nil;
            _descriptorPath = nil;
        }
        
        if (mostShallowIndexEntry) {
            _indexDirPath = [mostShallowIndexEntry stringByDeletingLastPathComponent];
            _isLayoutValid = YES;
        }

        if (_descriptorPath) {
            NSString *descriptorDir = [_descriptorPath stringByDeletingLastPathComponent];
            if (![_indexDirPath isEqualToString:descriptorDir]) {
                _descriptorPath = nil;
            }
        }
    }
}

@end


@implementation ZippedHtmlImportProcess
{
    NSURL *_reportBaseDir;
}

- (instancetype)initWithReport:(Report *)report
    destDir:(NSURL *)destDir
    zipFile:(ZipFile *)zipFile
    fileManager:(NSFileManager *)fileManager
{
    ValidateHtmlLayoutOperation *validation = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

    MkdirOperation *makeDestDir = [[MkdirOperation alloc] init];
    [makeDestDir addDependency:validation];

    UnzipOperation *unzip = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:nil];
    [unzip addDependency:makeDestDir];

    ParseJsonOperation *parseMetaData = [[ParseJsonOperation alloc] init];
    [parseMetaData addDependency:unzip];

    DeleteFileOperation *deleteZip = [[DeleteFileOperation alloc] initWithFileUrl:report.url fileManager:fileManager];
    [deleteZip addDependency:unzip];

    self = [super initWithReport:report steps:@[
        validation,
        makeDestDir,
        unzip,
        parseMetaData,
        deleteZip,
    ]];

    if (!self) {
        return nil;
    }

    _destDir = destDir;

    return self;
}

- (void)stepWillFinish:(NSOperation *)step stepIndex:(NSUInteger)stepIndex
{
    NSAssert((stepIndex < self.steps.count && self.steps[stepIndex] == step),
        @"operation %@ at index %u does not belong to %@", step, stepIndex, self);

    switch (stepIndex) {
        case 0:
            [self validateStepWillFinish];
            break;
        case 1:
            [self makeDestDirStepWillFinish];
            break;
        case 2:
            [self unzipStepWillFinish];
            break;
        case 3:
            [self parseDescriptorStepWillFinish];
            break;
        default:
            break;
    }
}

- (void)validateStepWillFinish
{
    ValidateHtmlLayoutOperation *validateStep = self.steps.firstObject;
    MkdirOperation *makeDestDirStep = self.steps[1];
    ParseJsonOperation *parseDescriptorStep = self.steps[3];

    if (!validateStep.isLayoutValid) {
        [self cancelStepsAfterStep:validateStep];
        return;
    }

    NSURL *destDir = self.destDir;
    if (validateStep.indexDirPath.length == 0) {
        NSString *reportName = [self.report.url.lastPathComponent stringByDeletingPathExtension];
        _reportBaseDir = [self.destDir URLByAppendingPathComponent:reportName isDirectory:YES];
        destDir = _reportBaseDir;
    }
    else {
        _reportBaseDir = [self.destDir URLByAppendingPathComponent:validateStep.indexDirPath isDirectory:YES];
    }

    makeDestDirStep.dirUrl = destDir;

    if (validateStep.hasDescriptor) {
        parseDescriptorStep.jsonUrl = [_reportBaseDir URLByAppendingPathComponent:validateStep.descriptorPath.lastPathComponent];
    }
    else {
        [parseDescriptorStep cancel];
    }
}

- (void)makeDestDirStepWillFinish
{
    MkdirOperation *makeDestDirStep = self.steps[1];

    if (!(makeDestDirStep.dirWasCreated || makeDestDirStep.dirExisted)) {
        [self cancelStepsAfterStep:makeDestDirStep];
        return;
    }

    UnzipOperation *unzipStep = self.steps[2];
    unzipStep.destDir = makeDestDirStep.dirUrl;
}

- (void)unzipStepWillFinish
{
    UnzipOperation *unzip = self.steps[2];

    if (!unzip.wasSuccessful) {
        [self cancelStepsAfterStep:unzip];
        return;
    }

    [self.report performSelectorOnMainThread:@selector(setUrl:) withObject:_reportBaseDir waitUntilDone:NO];
}

- (void)parseDescriptorStepWillFinish
{
    ParseJsonOperation *parseDescriptor = self.steps[3];
    [self.report performSelectorOnMainThread:@selector(setPropertiesFromJsonDescriptor:) withObject:parseDescriptor.parsedJsonDictionary waitUntilDone:NO];
}

- (void)cancelStepsAfterStep:(NSOperation *)step
{
    NSUInteger stepIndex = [self.steps indexOfObject:step];
    while (++stepIndex < self.steps.count) {
        NSOperation *pendingStep = self.steps[stepIndex];
        [pendingStep cancel];
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: %@", NSStringFromClass([self class]), self.report.url];
}

@end


@interface HtmlReportType ()

@property (strong, nonatomic, readonly) NSFileManager *fileManager;

@end


@implementation HtmlReportType

- (HtmlReportType *)initWithFileManager:(NSFileManager *)fileManager
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


- (id<ImportProcess>)createImportProcessForReport:(Report *)report
{
    ZipFile *zipFile = [[ZipFile alloc] initWithFileName:report.url.path mode:ZipFileModeUnzip];
    ZippedHtmlImportProcess *process = [[ZippedHtmlImportProcess alloc] initWithReport:report
        destDir:nil zipFile:zipFile fileManager:self.fileManager];

    return process;
}

@end
