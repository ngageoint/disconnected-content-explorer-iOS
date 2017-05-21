//
// Created by Robert St. John on 5/14/17.
// Copyright (c) 2017 mil.nga. All rights reserved.
//

#import "DICEDeleteReportProcess.h"
#import "FileOperations.h"
#import "Report.h"
#import "ImportProcess+Internal.h"

@implementation DICEDeleteReportProcess
{
    MoveFileOperation *_moveContentToTrash;
    MoveFileOperation *_moveSourceFileToTrash;
    DeleteFileOperation *_deleteFromTrash;
    dispatch_queue_t _moveCountQueue;
    NSUInteger _filesRemainingToMove;
}

- (instancetype)initWithReport:(Report *)report trashDir:(NSURL *)trashDir fileManager:(NSFileManager *)fileManager
{
    self = [super initWithReport:report];

    if (!self) {
        return nil;
    }

    _trashDir = trashDir;
    _fileManager = fileManager;
    NSString *trashContainerName = [NSUUID UUID].UUIDString;
    _trashContainerDir = [_trashDir URLByAppendingPathComponent:trashContainerName isDirectory:YES];
    _moveCountQueue = dispatch_queue_create("dice.DICEDeleteReportProcess_move_count", DISPATCH_QUEUE_SERIAL);

    MkdirOperation *makeTrashDir = [[MkdirOperation alloc] initWithDirUrl:_trashContainerDir fileManager:_fileManager];
    makeTrashDir.queuePriority = NSOperationQueuePriorityHigh;
    makeTrashDir.qualityOfService = NSQualityOfServiceUserInitiated;

    _deleteFromTrash = [[DeleteFileOperation alloc] initWithFileUrl:nil fileManager:_fileManager];
    _deleteFromTrash.queuePriority = NSOperationQueuePriorityLow;
    _deleteFromTrash.qualityOfService = NSQualityOfServiceBackground;

    NSMutableArray *steps = [NSMutableArray array];

    BOOL isDir = NO;
    if (report.importDir && [_fileManager fileExistsAtPath:report.importDir.path isDirectory:&isDir] && isDir) {
        NSURL *trashImportDir = [_trashContainerDir URLByAppendingPathComponent:report.importDir.lastPathComponent isDirectory:YES];
        _moveContentToTrash = [[MoveFileOperation alloc] initWithSourceUrl:report.importDir destUrl:trashImportDir fileManager:_fileManager];
        _moveContentToTrash.queuePriority = NSOperationQueuePriorityHigh;
        _moveContentToTrash.qualityOfService = NSQualityOfServiceUserInitiated;
        [_moveContentToTrash addDependency:makeTrashDir];
        [_deleteFromTrash addDependency:_moveContentToTrash];
        [steps addObject:_moveContentToTrash];
        _filesRemainingToMove += 1;
    }

    if (report.sourceFile && [_fileManager fileExistsAtPath:report.sourceFile.path]) {
        NSURL *trashSourceFile = [_trashContainerDir URLByAppendingPathComponent:report.sourceFile.lastPathComponent];
        _moveSourceFileToTrash = [[MoveFileOperation alloc] initWithSourceUrl:report.sourceFile destUrl:trashSourceFile fileManager:_fileManager];
        _moveSourceFileToTrash.queuePriority = NSOperationQueuePriorityHigh;
        _moveSourceFileToTrash.qualityOfService = NSQualityOfServiceUserInitiated;
        [_moveSourceFileToTrash addDependency:makeTrashDir];
        [_deleteFromTrash addDependency:_moveSourceFileToTrash];
        [steps addObject:_moveSourceFileToTrash];
        _filesRemainingToMove += 1;
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

    dispatch_sync(_moveCountQueue, ^{
        _filesRemainingToMove -= 1;
        if (_filesRemainingToMove > 0) {
            return;
        }
        if (self.delegate && [self.delegate conformsToProtocol:@protocol(DICEDeleteReportProcessDelegate)]) {
            [((id<DICEDeleteReportProcessDelegate>)self.delegate) filesDidMoveToTrashByDeleteReportProcess:self];
        }
        _deleteFromTrash.fileUrl = self.trashContainerDir;
    });
}

@end
