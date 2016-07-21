//
//  ZippedHtmlImportProcess.m
//  DICE
//
//  Created by Robert St. John on 12/21/15.
//  Copyright © 2015 National Geospatial-Intelligence Agency. All rights reserved.
//


#import "ImportProcess+Internal.h"
#import "FileOperations.h"
#import "ParseJsonOperation.h"
#import "ValidateHtmlLayoutOperation.h"
#import "UnzipOperation.h"
#import "ZippedHtmlImportProcess.h"
#import "ZipFile+FileTree.h"


@implementation ZippedHtmlImportProcess
{
    NSURL *_reportBaseDir;
    BOOL _descriptorParsed;
    BOOL _zipDeleted;
}

- (instancetype)initWithReport:(Report *)report
                       destDir:(NSURL *)destDir
                       zipFile:(ZipFile *)zipFile
                   fileManager:(NSFileManager *)fileManager
{
    self = [super initWithReport:report];
    if (!self) {
        return nil;
    }

    ValidateHtmlLayoutOperation *validation = [[ValidateHtmlLayoutOperation alloc] initWithFileListing:[zipFile fileTree_enumerateFiles]];

    MkdirOperation *makeDestDir = [[MkdirOperation alloc] initWithFileMananger:fileManager];
    [makeDestDir addDependency:validation];

    UnzipOperation *unzip = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:nil fileManager:fileManager];
    [unzip addDependency:makeDestDir];
    unzip.delegate = self;

    ParseJsonOperation *parseMetaData = [[ParseJsonOperation alloc] init];
    [parseMetaData addDependency:unzip];

    DeleteFileOperation *deleteZip = [[DeleteFileOperation alloc] initWithFileUrl:report.url fileManager:fileManager];
    [deleteZip addDependency:unzip];

    _destDir = destDir;
    self.steps = @[validation, makeDestDir, unzip, parseMetaData, deleteZip];

    return self;
}

- (void)stepWillFinish:(NSOperation *)step
{
    NSUInteger stepIndex = [self.steps indexOfObject:step];
    switch (stepIndex) {
        case ZippedHtmlImportValidateStep:
            [self validateStepWillFinish];
            break;
        case ZippedHtmlImportMakeBaseDirStep:
            [self makeDestDirStepWillFinish];
            break;
        case ZippedHtmlImportUnzipStep:
            [self unzipStepWillFinish];
            break;
        case ZippedHtmlImportParseDescriptorStep:
            [self parseDescriptorStepWillFinish];
            break;
        case ZippedHtmlImportDeleteStep:
            [self deleteStepWillFinish];
            break;
        default:
            break;
    }
}

- (void)validateStepWillFinish
{
    ValidateHtmlLayoutOperation *validateStep = (ValidateHtmlLayoutOperation *)self.steps[ZippedHtmlImportValidateStep];
    MkdirOperation *makeDestDirStep = (MkdirOperation *)self.steps[ZippedHtmlImportMakeBaseDirStep];
    ParseJsonOperation *parseDescriptorStep = (ParseJsonOperation *)self.steps[ZippedHtmlImportParseDescriptorStep];

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
        _descriptorParsed = YES;
    }
}

- (void)makeDestDirStepWillFinish
{
    MkdirOperation *makeDestDirStep = (MkdirOperation *)self.steps[ZippedHtmlImportMakeBaseDirStep];

    if (!(makeDestDirStep.dirWasCreated || makeDestDirStep.dirExisted)) {
        [self cancelStepsAfterStep:makeDestDirStep];
        return;
    }

    UnzipOperation *unzipStep = (UnzipOperation *)self.steps[ZippedHtmlImportUnzipStep];
    unzipStep.destDir = makeDestDirStep.dirUrl;
}

- (void)unzipStepWillFinish
{
    UnzipOperation *unzip = (UnzipOperation *) self.steps[ZippedHtmlImportUnzipStep];

    if (!unzip.wasSuccessful) {
        [self cancelStepsAfterStep:unzip];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
       self.report.url = _reportBaseDir;
    });
}

- (void)parseDescriptorStepWillFinish
{
    ParseJsonOperation *parseDescriptor = (ParseJsonOperation *) self.steps[ZippedHtmlImportParseDescriptorStep];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.report setPropertiesFromJsonDescriptor:parseDescriptor.parsedJsonDictionary];
    });
    _descriptorParsed = YES;
    [self notifyDelegateIfFinished];
}

- (void)deleteStepWillFinish
{
    _zipDeleted = YES;
    [self notifyDelegateIfFinished];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@: %@", NSStringFromClass([self class]), self.report.url];
}

- (void)unzipOperation:(UnzipOperation *)op didUpdatePercentComplete:(NSUInteger)percent
{
    self.report.summary = [NSString stringWithFormat:@"Unzipping... %lu%% complete", (unsigned long)percent];
    [self.delegate reportWasUpdatedByImportProcess:self];
}

- (void)notifyDelegateIfFinished
{
    if (_zipDeleted && _descriptorParsed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate importDidFinishForImportProcess:self];
        });
    }
}

@end
