//
//  ReportMapAnnotation.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "Report.h"

@interface ReportMapAnnotation : MKPointAnnotation 

@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@property (nonatomic, strong) Report *report;
@property (nonatomic, copy) NSString *title;

- (id)initWithTitle:(NSString*)title coordinate:(CLLocationCoordinate2D)coordinate;
- (id) initWithReport: (Report *)report;

@end
