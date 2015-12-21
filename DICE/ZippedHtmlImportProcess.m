//
//  ZippedHtmlImportProcess.m
//  DICE
//
//  Created by Robert St. John on 12/21/15.
//  Copyright © 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "ZippedHtmlImportProcess.h"

#import "FileOperations.h"
#import "ParseJsonOperation.h"
#import "ValidateHtmlLayoutOperation.h"



@implementation ZippedHtmlImportProcess
{
    NSURL *_reportBaseDir;
    NSArray *_steps;
}

- (instancetype)initWithReport:(Report *)report
                       destDir:(NSURL *)destDir
                       zipFile:(ZipFile *)zipFile
                   fileManager:(NSFileManager *)fileManager
{
    self = [super initWithReport:report];

    ValidateHtmlLayoutOperation *validation = [[ValidateHtmlLayoutOperation alloc] initWithZipFile:zipFile];

    MkdirOperation *makeDestDir = [[MkdirOperation alloc] init];
    [makeDestDir addDependency:validation];

    UnzipOperation *unzip = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:nil fileManager:fileManager];
    [unzip addDependency:makeDestDir];
    unzip.delegate = self;

    ParseJsonOperation *parseMetaData = [[ParseJsonOperation alloc] init];
    [parseMetaData addDependency:unzip];

    DeleteFileOperation *deleteZip = [[DeleteFileOperation alloc] initWithFileUrl:report.url fileManager:fileManager];
    [deleteZip addDependency:unzip];

    _steps = [NSArray arrayWithObjects:validation, makeDestDir, unzip, parseMetaData, deleteZip, nil];

    if (!self) {
        return nil;
    }

    _destDir = destDir;

    return self;
}

- (void)stepWillFinish:(NSOperation *)step
{
    //    switch (stepIndex) {
    //        case 0:
    //            [self validateStepWillFinish];
    //            break;
    //        case 1:
    //            [self makeDestDirStepWillFinish];
    //            break;
    //        case 2:
    //            [self unzipStepWillFinish];
    //            break;
    //        case 3:
    //            [self parseDescriptorStepWillFinish];
    //            break;
    //        default:
    //            break;
    //    }
}

- (void)validateStepWillFinish
{
    ValidateHtmlLayoutOperation *validateStep = _steps.firstObject;
    MkdirOperation *makeDestDirStep = _steps[1];
    ParseJsonOperation *parseDescriptorStep = _steps[3];

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
    MkdirOperation *makeDestDirStep = _steps[1];

    if (!(makeDestDirStep.dirWasCreated || makeDestDirStep.dirExisted)) {
        [self cancelStepsAfterStep:makeDestDirStep];
        return;
    }

    UnzipOperation *unzipStep = _steps[2];
    unzipStep.destDir = makeDestDirStep.dirUrl;
}

- (void)unzipStepWillFinish
{
    UnzipOperation *unzip = _steps[2];

    if (!unzip.wasSuccessful) {
        [self cancelStepsAfterStep:unzip];
        return;
    }

    [self.report performSelectorOnMainThread:@selector(setUrl:) withObject:_reportBaseDir waitUntilDone:NO];
}

- (void)parseDescriptorStepWillFinish
{
    ParseJsonOperation *parseDescriptor = _steps[3];
    [self.report performSelectorOnMainThread:@selector(setPropertiesFromJsonDescriptor:) withObject:parseDescriptor.parsedJsonDictionary waitUntilDone:NO];
}

- (void)cancelStepsAfterStep:(NSOperation *)step
{
    NSUInteger stepIndex = [_steps indexOfObject:step];
    while (++stepIndex < _steps.count) {
        NSOperation *pendingStep = _steps[stepIndex];
        [pendingStep cancel];
    }
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

@end
