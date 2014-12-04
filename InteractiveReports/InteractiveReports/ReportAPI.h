//
//  ReportAPI.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "Report.h"


@interface ReportNotification : NSObject 

+ (NSString *)reportAdded;
+ (NSString *)reportUpdated;
//+ (NSString *)reportImportBegan;
+ (NSString *)reportImportProgress;
+ (NSString *)reportImportFinished;
+ (NSString *)reportsLoaded;

@end

@interface ReportAPI : NSObject

+ (ReportAPI*)sharedInstance;

- (void)importReportFromUrl:(NSURL *)reportUrl afterImport:(void(^)(Report *))afterImportBlock;
- (NSMutableArray*)getReports;
- (void)loadReports;
- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler;
- (Report *)reportForID:(NSString *)reportID;

@end
