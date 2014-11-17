//
//  ReportAPI.m
//  InteractiveReports
//

#import "ReportAPI.h"

@interface ReportAPI () {
    BOOL isOnline;
    LocalReportManager *localReportManager;
}
@end


@implementation ReportAPI

- (id)init
{
    self = [super init];
    
    if (self)
    {
        isOnline = NO;
        localReportManager = [[LocalReportManager alloc] init];
    }
    
    return self;
}


+ (ReportAPI*)sharedInstance
{
    static ReportAPI *_sharedInstance = nil;
    static dispatch_once_t oncePredicate;
    
    // Use grand central dispatch to execute the initialization of the ReportAPI once and only once.
    dispatch_once(&oncePredicate, ^{
        _sharedInstance = [[ReportAPI alloc] init];
    });
    
    return _sharedInstance;
}


- (NSMutableArray*)getReports
{
    return [localReportManager getReports];
}


- (void)loadReports
{
    [localReportManager loadReports];
}


- (void)loadReportsWithCompletionHandler:(void(^) (void))completionHandler
{
    [localReportManager loadReportsWithCompletionHandler:^{
        completionHandler();
    }];
}

@end
