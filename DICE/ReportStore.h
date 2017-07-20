//
//  ReportStore.h
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol DICEArchiveFactory;
@protocol ReportType;
@class DICEUtiExpert;
@class Report;

#import "ImportProcess.h"
#import "DICEDownloadManager.h"


@interface ReportStore : NSObject <ImportDelegate, DICEDownloadDelegate>

@property (class, nonnull) ReportStore *sharedInstance;

/**
 The list of ReportType objects for handling report files
 */
@property (nonnull, readonly) NSArray<id<ReportType>> *reportTypes;
@property (nonnull, readonly) NSURL *reportsDir;
@property (nonnull, readonly) NSCompoundPredicate *reportsDirExclusions;
@property (nonnull, readonly) DICEUtiExpert *utiExpert;
@property (nonnull, readonly) id<DICEArchiveFactory> archiveFactory;
@property (nonnull, nonatomic) DICEDownloadManager *downloadManager;
@property (nonnull, readonly) NSOperationQueue *importQueue;
@property (nonnull, readonly) NSFileManager *fileManager;
@property (nonnull, readonly) NSManagedObjectContext *reportDb;
@property (weak, nullable, readonly) UIApplication *application;

/**
 Initialize a ReportStore object with the given NSFileManager and reports directory.

 This is the NS_DESIGNATED_INITIALIZER for this class.
 
 @param reportsDir the NSURL that points to the directory where report files reside
 @param fileManager the NSFileManager instance that this ReportStore will use to conduct file system operations

 @return the initialized ReportStore
 */
- (nullable instancetype)initWithReportTypes:(NSArray<id<ReportType>> * _Nonnull)reportTypes
    reportsDir:(nonnull NSURL *)reportsDir
    exclusions:(nullable NSArray<NSPredicate *> *)exclusions
    utiExpert:(nonnull DICEUtiExpert *)utiExpert
    archiveFactory:(nonnull id<DICEArchiveFactory>)archiveFactory
    importQueue:(nonnull NSOperationQueue *)importQueue
    fileManager:(nonnull NSFileManager *)fileManager
    reportDb:(nonnull NSManagedObjectContext *)reportDb
    application:(nonnull UIApplication *)application
    NS_DESIGNATED_INITIALIZER;

- (void)addReportsDirExclusion:(nonnull NSPredicate *)rule;

/**
 Load/refresh the list of reports based on the contents of the app's file system.
 Most of the work of loading reports will be done asynchronously, so this method
 will return quickly.
 */
- (void)loadContentFromReportsDir;

/**
 Import the resource the given URL references as a Report.  The import will occur
 asynchronously.

 @param reportUrl (NSURL *) the URL of the resource to import
 */
- (void)attemptToImportReportFromResource:(nonnull NSURL *)reportUrl;

/**
 Try again to import the content for the given report.  The given report's import
 status must be ReportImportStatusFailed, or this method will do nothing.
 */
- (void)retryImportingReport:(nonnull Report *)report;

- (nullable Report *)reportForContentId:(nonnull NSString *)contentId;

- (void)deleteReport:(nonnull Report *)report;

- (void)resumePendingImports;

- (void)suspendPendingImports;

@end
