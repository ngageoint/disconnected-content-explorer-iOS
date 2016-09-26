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


/**
 This class provides static methods that return strings for notification names that
 ReportStore can produce.  ReportStore will fire all noifications on the main thread.
 */
@interface ReportNotification : NSObject

/**
 This notification indicates a report was added to the list.
 This does not mean the report is imported and ready to view.
 The NSNotification object userInfo dicationary contains
 {
     @"report": (Report*) the added report object,
     @"index": (NSString*) integral index of the report in the reports array
 }
 */
+ (nonnull NSString *)reportAdded;
/**
 This notification indicates that the app has started importing
 a given report.
 The NSNotification object userInfo dictionary contains
 {
     @"report": (Report*) the report being imported,
     @"index": (NSString*) integral index of the report in the reports array
 }
 */
+ (nonnull NSString *)reportImportBegan;
/**
 This notification indicates progress on importing a given report.
 The NSNotification object userInfo dictionary contains
 {
     @"report": (Report*) the report object being imported,
     @"percentExtracted": (NSNumber*) integral percentage of report content extracted from archive
 }
 */
+ (nonnull NSString *)reportExtractProgress;
/**
 This notification indicates that a report was fully
 imported and is ready to view.
 The NSNotificatoin object userInfo dictionary contains
 {
     @"report": (Report*) the report that was imported,
     @"index": (NSString*) integral index of the report in the reports array
 }
 */
+ (nonnull NSString *)reportImportFinished;
/**
 This notification indicates that ReportStore has finished scanning for report files
 in the Documents directory and has populated the report list with its findings.
 The reports in the list may still be pending the import process, however, so
 may not yet be ready to view.
 The NSNotification object has a nil userInfo dictionary.
 */
+ (nonnull NSString *)reportsLoaded;

@end




@interface ReportStore : NSObject <ImportDelegate>


+ (nullable instancetype)sharedInstance;


/**
 The list of Report objects
 */
@property (nonnull, readonly) NSArray<Report *> *reports;

/**
 The list of ReportType objects for handling report files
 */
@property (nonnull) NSArray<id<ReportType>> *reportTypes;
@property (nonnull, readonly) NSURL *reportsDir;
@property (nonnull, readonly) DICEUtiExpert *utiExpert;
@property (nonnull, readonly) id<DICEArchiveFactory> archiveFactory;
@property (nonnull, readonly) NSOperationQueue *importQueue;
@property (nonnull, readonly) NSFileManager *fileManager;
@property (weak, nullable, readonly) UIApplication *application;

/**
 Initialize a ReportStore object with the given NSFileManager and reports directory.

 This is the NS_DESIGNATED_INITIALIZER for this class.
 
 @param reportsDir the NSURL that points to the directory where report files reside
 @param fileManager the NSFileManager instance that this ReportStore will use to conduct file system operations

 @return the initialized ReportStore
 */
- (nullable instancetype)initWithReportsDir:(nonnull NSURL *)reportsDir
    fileManager:(nonnull NSFileManager *)fileManager
    archiveFactory:(nonnull id<DICEArchiveFactory>)archiveFactory
    utiExpert:(nonnull DICEUtiExpert *)utiExpert
    importQueue:(nonnull NSOperationQueue *)importQueue NS_DESIGNATED_INITIALIZER;

/**
 Load/refresh the list of reports based on the contents of the app's file system.
 Most of the work of loading reports will be done asynchronously, so this method
 will return quickly, but the Report objects in the list may not be enabled until
 all processing is complete.  If a load is currently in progress, this method will
 return nil.
 
 @return (NSArray *) the list of Report objects that were found
 */
- (nonnull NSArray<Report *> *)loadReports;

/**
 Import the resource the given URL references as a Report.  The import will occur
 asynchronously, but can fail fast and return nil if ReportStore can immediately
 determine that it does not support the given resource.  The returned Report
 object will be added to the report list.

 @param reportUrl (NSURL *) the URL of the resource to import

 @return (Report *) the initial Report object that will represent the report,
    or nil if the given resource cannot be imported
 */
- (nullable Report *)attemptToImportReportFromResource:(nonnull NSURL *)reportUrl;

- (nullable Report *)reportForID:(nonnull NSString *)reportID;

@end
