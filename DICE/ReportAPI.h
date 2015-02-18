//
//  ReportAPI.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "Report.h"


@interface ReportNotification : NSObject 

/**
 This notification indicates a report was added to the list.
 This does not mean the report is imported and ready to view.
 */
+ (NSString *)reportAdded;
+ (NSString *)reportImportBegan;
+ (NSString *)reportImportProgress;
/**
 This notification indicates that a report was fully
 imported and is ready to view.  This notification will 
 always dispatch on the main thread.
 */
+ (NSString *)reportImportFinished;
+ (NSString *)reportsLoaded;

@end

@interface ReportAPI : NSObject

+ (ReportAPI*)sharedInstance;
+ (NSString *)userGuideReportID;

- (void)importReportFromUrl:(NSURL *)reportURL afterImport:(void(^)(Report *))afterImportBlock;
- (NSMutableArray*)getReports;
- (void)loadReports;
- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler;
- (Report *)reportForID:(NSString *)reportID;

@end
