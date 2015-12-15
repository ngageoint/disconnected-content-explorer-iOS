//
//  ReportStore.h
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Report.h"
#import "ImportProcess.h"
#import "ReportType.h"


@interface ReportStore : NSObject <ImportDelegate>

/**
 The list of ReportType objects for handling report files
 */
@property NSArray<id<ReportType>> *reportTypes;

/**
 The list of Report objects
 */
@property NSArray<Report *> *reports;


/**
 Initialize a ReportStore object with the given NSFileManager and reports directory.

 This is the NS_DESIGNATED_INITIALIZER for this class.
 
 @param reportsDir the NSURL that points to the directory where report files reside
 @param fileManager the NSFileManager instance that this ReportStore will use to conduct file system operations

 @return the initialized ReportStore
 */
- (instancetype)initWithReportsDir:(NSURL *)reportsDir fileManager:(NSFileManager *)fileManager NS_DESIGNATED_INITIALIZER;

/**
 Load/refresh the list of reports based on the contents of the app's file system.
 Most of the work of loading reports will be done asynchronously, so this method
 will return quickly, but the Report objects in the list may not be enabled until
 all processing is complete.  If a load is currently in progress, this method will
 return nil.
 
 @return (NSArray *) the list of Report objects that were found
 */
- (NSArray<Report *> *)loadReports;

/**
 Import the resource the given URL references as a Report.  The import will occur
 asynchronously, but can fail fast and return nil if ReportStore can immediately
 determine that it does not support the given resource.  The returned Report
 object will be added to the report list.

 @param reportUrl (NSURL *) the URL of the resource to import

 @return (Report *) the initial Report object that will represent the report,
    or nil if the given resource cannot be imported
 */
- (Report *)attemptToImportReportFromResource:(NSURL *)reportUrl;

@end
