//
// Created by Robert St. John on 9/13/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface TestImportProcess : ImportProcess

@property BOOL failed;

- (instancetype)initWithReport:(Report *)report NS_DESIGNATED_INITIALIZER;
- (instancetype)block;
- (instancetype)unblock;
- (instancetype)cancelAll;

@end


@interface TestReportType : NSObject <ReportType>

@property (readonly) NSString *extension;
@property (readonly) NSFileManager *fileManager;
@property NSMutableArray<TestImportProcess *> *importProcessQueue;

- (instancetype)initWithExtension:(NSString *)ext fileManager:(NSFileManager *)fileManager NS_DESIGNATED_INITIALIZER;
- (TestImportProcess *)enqueueImport;

@end


@interface TestReportTypeMatchPredicate : NSObject <ReportTypeMatchPredicate>

@property (readonly) BOOL hasMultipleRootEntries;

- (instancetype)initWithType:(TestReportType *)type;

@end
