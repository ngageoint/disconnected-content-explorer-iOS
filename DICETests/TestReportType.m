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


@interface TestReportTypeMatchPredicate : NSObject <ReportTypeMatchPredicate>

- (instancetype)initWithType:(TestReportType *)type;

@end


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

- (void)considerContentWithName:(NSString *)name probableUti:(CFStringRef)uti
{
    _foundContentWithTypeExt = _foundContentWithTypeExt || [name.pathExtension isEqualToString:_type.extension];
}

@end


@implementation TestImportProcess

- (instancetype)init
{
    self = [self initWithReport:nil];
    return self;
}

- (instancetype)initWithReport:(Report *)report
{
    self = [super initWithReport:report];

    TestImportProcess *my = self;
    NSBlockOperation *op1 = [NSBlockOperation blockOperationWithBlock:^{
        my.report.summary = @"op1:finished";
        [my.delegate reportWasUpdatedByImportProcess:my];
    }];
    NSBlockOperation *op2 = [NSBlockOperation blockOperationWithBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            my.report.title = @"finished";
            my.report.summary = @"finished";
            [my.delegate reportWasUpdatedByImportProcess:my];
            [my.delegate importDidFinishForImportProcess:my];
        });
    }];
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

- (BOOL)isFinished
{
    @synchronized (self) {
        return self.report.isEnabled;
    }
}

@end



@implementation TestReportType

- (instancetype)init
{
    return [self initWithExtension:nil];
}

- (instancetype)initWithExtension:(NSString *)ext
{
    if (!ext) {
        [NSException raise:NSInvalidArgumentException format:@"ext is nil"];
    }
    self = [super init];
    _extension = ext;
    _importProcessQueue = [NSMutableArray array];
    return self;
}

- (TestImportProcess *)enqueueImport
{
    @synchronized (self) {
        TestImportProcess *proc = [[TestImportProcess alloc] init];
        [self.importProcessQueue addObject:proc];
        return proc;
    }
}

- (BOOL)couldImportFromPath:(NSURL *)path
{
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

@end