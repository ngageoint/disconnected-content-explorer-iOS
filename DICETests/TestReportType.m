//
// Created by Robert St. John on 9/13/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "NSOperation+Blockable.h"
#import "ImportProcess+Internal.h"
#import <Expecta/Expecta.h>
#import "ReportType.h"
#import "TestReportType.h"
#import "Report.h"


@implementation TestReportTypeMatchPredicate {
    TestReportType *_type;
    BOOL _foundContentWithTypeExt;
}

- (instancetype)initWithType:(TestReportType *)type
{
    self = [super init];
    _type = type;
    _foundContentWithTypeExt = NO;
    return self;
}

- (id<ReportType>)reportType
{
    return _type;
}

- (BOOL)contentCouldMatch
{
    return _foundContentWithTypeExt;
}

- (void)considerContentEntryWithName:(NSString *)name probableUti:(CFStringRef)uti contentInfo:(ContentEnumerationInfo *)info
{
    if (info.baseDir && info.baseDir.length == 0) {
        _hasMultipleRootEntries = YES;
    }
    _foundContentWithTypeExt = _foundContentWithTypeExt || [name.pathExtension isEqualToString:_type.extension];
}

@end


@implementation TestImportProcess

- (instancetype)initWithReport:(Report *)report
{
    return [self initWithTypeExtension:nil report:report];
}

- (instancetype)initWithTypeExtension:(NSString *)ext
{
    return [self initWithTypeExtension:ext report:nil];
}

- (instancetype)initWithTypeExtension:(NSString *)ext report:(Report *)report
{
    self = [super initWithReport:report];

    self.typeExtension = ext;

    TestImportProcess *my = self;
    NSBlockOperation *op1 = [NSBlockOperation blockOperationWithBlock:^{
        [my.delegate reportWasUpdatedByImportProcess:my];
    }];
    NSBlockOperation *op2 = [NSBlockOperation blockOperationWithBlock:^{
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (my.report.baseDir && !my.report.rootFile) {
                NSString *indexName = [NSString stringWithFormat:@"index.%@", self.typeExtension];
                my.report.rootFile = [my.report.baseDir URLByAppendingPathComponent:indexName];
            }
            [my.delegate reportWasUpdatedByImportProcess:my];
        });
    }];
    op1.name = @"TestImportProcess-1";
    op2.name = @"TestImportProcess-2";
    [op2 addDependency:op1];
    self.steps = @[op1, op2];

    return self;
}

- (instancetype)cancelAll
{
    self.steps = @[];
    return self;
}

- (instancetype)block
{
    [self.steps.firstObject block];
    return self;
}

- (instancetype)unblock
{
    [self.steps.firstObject unblock];
    return self;
}

- (BOOL)wasSuccessful
{
    return !self.failed && super.wasSuccessful;
}

@end



@implementation TestReportType

- (instancetype)init
{
    return [self initWithExtension:nil fileManager:nil];
}

- (instancetype)initWithExtension:(NSString *)ext fileManager:(NSFileManager *)fileManager
{
    if (!ext) {
        [NSException raise:NSInvalidArgumentException format:@"ext is nil"];
    }
    self = [super init];
    _extension = ext;
    _fileManager = fileManager;
    _importProcessQueue = [NSMutableArray array];
    return self;
}

- (TestImportProcess *)enqueueImport
{
    @synchronized (self) {
        TestImportProcess *proc = [[TestImportProcess alloc] initWithTypeExtension:self.extension];
        [self.importProcessQueue addObject:proc];
        return proc;
    }
}

- (BOOL)couldImportFromPath:(NSURL *)path
{
    if ([path.absoluteString hasSuffix:@"/"]) {
        NSString *index = [NSString stringWithFormat:@"index.%@", self.extension];
        return [self.fileManager fileExistsAtPath:[path.path stringByAppendingPathComponent:index]];
    }
    return [path.pathExtension isEqualToString:self.extension];
}

- (id<ReportTypeMatchPredicate>)createContentMatchingPredicate
{
    return [[TestReportTypeMatchPredicate alloc] initWithType:self];
}

- (ImportProcess *)createProcessToImportReport:(Report *)report toDir:(NSURL *)destDir
{
    @synchronized (self) {
        if (self.importProcessQueue.count) {
            TestImportProcess *proc = self.importProcessQueue.firstObject;
            [self.importProcessQueue removeObjectAtIndex:0];
            [proc setReport:report];
            return proc;
        }
    }
    failure([NSString stringWithFormat:@"tried to create process from empty to queue to import report %@", report]);
    return nil;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"TestReportType.%@ (%@)", self.extension, super.description];
}

@end
