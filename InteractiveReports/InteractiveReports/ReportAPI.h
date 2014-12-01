//
//  ReportAPI.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "Report.h"

@interface ReportAPI : NSObject

+ (ReportAPI*)sharedInstance;

- (void)importReportFromUrl:(NSURL *)reportUrl afterImport:(void(^) (void))finishBlock;
- (NSMutableArray*)getReports;
- (void)loadReports;
- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler;

@end
