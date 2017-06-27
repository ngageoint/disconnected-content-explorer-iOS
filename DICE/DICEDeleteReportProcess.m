//
// Created by Robert St. John on 5/14/17.
// Copyright (c) 2017 mil.nga. All rights reserved.
//

#import "DICEDeleteReportProcess.h"
#import "FileOperations.h"
#import "Report.h"
#import "ImportProcess+Internal.h"
#import <stdatomic.h>

@implementation DICEDeleteReportProcess
{
    MoveFileOperation *_moveContentToTrash;
    MoveFileOperation *_moveSourceFileToTrash;
    DeleteFileOperation *_deleteFromTrash;
    atomic_uint _filesRemainingToMove;
}

- (instancetype)initWithReport:(Report *)report trashDir:(NSURL *)trashDir preservingMetaData:(BOOL)preserveMetaData fileManager:(NSFileManager *)fileManager
{
    self = [super initWithReport:report];

    if (!self) {
        return nil;
    }

    _trashDir = trashDir;
    _isPreservingMetaData = preserveMetaData;
    _fileManager = fileManager;
    NSString *trashContainerName = [NSUUID UUID].UUIDString;
    _trashContainerDir = [_trashDir URLByAppendingPathComponent:trashContainerName isDirectory:YES];

    MkdirOperation *makeTrashDir = [[MkdirOperation alloc] initWithDirUrl:_trashContainerDir fileManager:_fileManager];
    makeTrashDir.queuePriority = NSOperationQueuePriorityHigh;
    makeTrashDir.qualityOfService = NSQualityOfServiceUserInitiated;

    _deleteFromTrash = [[DeleteFileOperation alloc] initWithFileUrl:nil fileManager:_fileManager];
    _deleteFromTrash.queuePriority = NSOperationQueuePriorityLow;
    _deleteFromTrash.qualityOfService = NSQualityOfServiceBackground;

    NSMutableArray *steps = [NSMutableArray array];

    NSURL *contentDir = preserveMetaData ? report.baseDir : report.importDir;

    BOOL isDir = NO;
    if (contentDir && [_fileManager fileExistsAtPath:contentDir.path isDirectory:&isDir] && isDir) {
        NSURL *trashContentDir = [_trashContainerDir URLByAppendingPathComponent:contentDir.lastPathComponent isDirectory:YES];
        _moveContentToTrash = [[MoveFileOperation alloc] initWithSourceUrl:contentDir destUrl:trashContentDir fileManager:_fileManager];
        _moveContentToTrash.queuePriority = NSOperationQueuePriorityHigh;
        _moveContentToTrash.qualityOfService = NSQualityOfServiceUserInitiated;
        [_moveContentToTrash addDependency:makeTrashDir];
        [_deleteFromTrash addDependency:_moveContentToTrash];
        [steps addObject:_moveContentToTrash];
        atomic_fetch_add(&_filesRemainingToMove, 1);
    }

    if (report.sourceFile && [_fileManager fileExistsAtPath:report.sourceFile.path]) {
        NSURL *trashSourceFile = [_trashContainerDir URLByAppendingPathComponent:report.sourceFile.lastPathComponent];
        _moveSourceFileToTrash = [[MoveFileOperation alloc] initWithSourceUrl:report.sourceFile destUrl:trashSourceFile fileManager:_fileManager];
        _moveSourceFileToTrash.queuePriority = NSOperationQueuePriorityHigh;
        _moveSourceFileToTrash.qualityOfService = NSQualityOfServiceUserInitiated;
        [_moveSourceFileToTrash addDependency:makeTrashDir];
        [_deleteFromTrash addDependency:_moveSourceFileToTrash];
        [steps addObject:_moveSourceFileToTrash];
        atomic_fetch_add(&_filesRemainingToMove, 1);
    }

    if (steps.count == 0) {
        [steps addObject:[NSBlockOperation blockOperationWithBlock:^{
            if (self.delegate && [self.delegate conformsToProtocol:@protocol(DICEDeleteReportProcessDelegate)]) {
                [(id<DICEDeleteReportProcessDelegate>)self.delegate noFilesFoundToDeleteByDeleteReportProcess:self];
            }
        }]];
    }
    else {
        [steps insertObject:makeTrashDir atIndex:0];
        [steps addObject:_deleteFromTrash];
    }

    self.steps = [NSArray arrayWithArray:steps];
    [steps removeAllObjects];

    return self;
}

- (void)stepWillFinish:(NSOperation *)step
{
    if (!(step == _moveContentToTrash || step == _moveSourceFileToTrash)) {
        return;
    }

    if (atomic_fetch_sub(&_filesRemainingToMove, 1) - 1) {
        return;
    }

    if (self.delegate && [self.delegate conformsToProtocol:@protocol(DICEDeleteReportProcessDelegate)]) {
        [((id<DICEDeleteReportProcessDelegate>)self.delegate) filesDidMoveToTrashByDeleteReportProcess:self];
    }
    _deleteFromTrash.fileUrl = self.trashContainerDir;
}

@end
