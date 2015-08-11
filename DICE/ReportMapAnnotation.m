//
//  ReportMapAnnotation.m
//  InteractiveReports
//

#import "ReportMapAnnotation.h"

@implementation ReportMapAnnotation

- (id)initWithTitle:(NSString*)title coordinate:(CLLocationCoordinate2D)coordinate
{
    if ((self = [super init]))
    {
        if ([title isKindOfClass:[NSString class]]) {
            self.title = title;
        }
        self.coordinate = coordinate;
    }
    
    return self;
}


- (id) initWithReport:(Report *)report
{
    if ((self = [super init])) {
        self.title = report.title;
        self.report = report;
        
        CLLocationCoordinate2D coordinate2;
        coordinate2.latitude = report.lat.doubleValue;
        coordinate2.longitude = report.lon.doubleValue;
        self.coordinate = coordinate2;
    }
    
    return self;
}

@end
