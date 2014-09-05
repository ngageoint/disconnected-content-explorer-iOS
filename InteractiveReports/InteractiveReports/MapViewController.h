//
//  MapViewController.h
//  InteractiveReports
//


#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import "ReportMapAnnotation.h"
#import "ReportViewController.h"
#import "TileViewController.h"
#import "Report.h"
#import "OfflineMapUtility.h"

@interface MapViewController : UIViewController <MKMapViewDelegate>

@property (strong, nonatomic) IBOutlet MKMapView *mapView;
@property (strong, nonatomic) NSMutableArray *reports;
@property (strong, nonatomic) Report *selectedReport;
@property (weak, nonatomic) IBOutlet UISegmentedControl *segmentedControl;

@end
