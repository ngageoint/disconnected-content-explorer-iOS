//
//  ReportAPI.m
//  InteractiveReports
//

#import "ReportAPI.h"

@interface ReportAPI () {
    BOOL isOnline;
    NSMutableArray *reports;
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
        reports = [[NSMutableArray alloc] init];
        localReportManager = [[LocalReportManager alloc]init];
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
    reports = [localReportManager getReports];
    return reports;
}


- (void)loadReports
{
    [localReportManager loadReports];
}


@end
