//
//  ReportAPI.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "LocalReportManager.h"
#import "Report.h"

@interface ReportAPI : NSObject

+ (ReportAPI*)sharedInstance;
- (NSMutableArray*)getReports;
- (void)loadReports;
- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler;

@end
