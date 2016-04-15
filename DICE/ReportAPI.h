//
//  ReportAPI.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "Report.h"


/**
 This class provides static methods that return strings for notification names that
 ReportAPI can produce.  ReportAPI will fire all noifications on the main thread.
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
+ (NSString *)reportAdded;
/**
 This notification indicates that the app has started importing
 a given report.
 The NSNotification object userInfo dictionary contains
 {
     @"report": (Report*) the report being imported,
     @"index": (NSString*) integral index of the report in the reports array
 }
 */
+ (NSString *)reportImportBegan;
/**
 This notification indicates progress on importing a given report.
 The NSNotification object userInfo dictionary contains
 {
     @"report": (Report*) the report object being imported,
     @"progress": (NSString*) integral number of files that have been imported,
     @"totalNumberOfFiles": (NSString*) integral total number for files the report contains
 }
 */
+ (NSString *)reportImportProgress;
/**
 This notification indicates that a report was fully
 imported and is ready to view.
 The NSNotificatoin object userInfo dictionary contains
 {
     @"report": (Report*) the report that was imported,
     @"index": (NSString*) integral index of the report in the reports array
 }
 */
+ (NSString *)reportImportFinished;
/**
 This notification indicates that ReportAPI has finished scanning for report files
 in the Documents directory and has populated the report list with its findings.
 The reports in the list may still be pending the import process, however, so 
 may not yet be ready to view.
 The NSNotification object has a nil userInfo dictionary.
 */
+ (NSString *)reportsLoaded;

@end

@interface ReportAPI : NSObject

+ (ReportAPI*)sharedInstance;
+ (NSString *)userGuideReportID;

- (void)importReportFromUrl:(NSURL *)reportURL afterImport:(void(^)(Report *))afterImportBlock;
- (NSArray*)getReports;
- (void)loadReports;
- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler;
- (Report *)reportForID:(NSString *)reportID;
- (void)downloadReportAtURL:(NSURL *)URL;
- (void)deleteReportAtIndexPath:(NSIndexPath *)indexPath;

@end
