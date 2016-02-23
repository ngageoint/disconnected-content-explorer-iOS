//
//  MapViewController.m
//  InteractiveReports
//

#import "MapViewController.h"
#import "GeoPackageMapOverlays.h"

#define METERS_PER_MILE = 1609.344

@interface MapViewController ()

@property (weak, nonatomic) IBOutlet UIView *noLocationsView;
@property (nonatomic, strong) GeoPackageMapOverlays * geoPackageOverlays;

@end

@implementation MapViewController {
    BOOL polygonsAdded;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.noLocationsView.layer.cornerRadius = 10.0;
    self.mapView.delegate = self;
    polygonsAdded = NO;
    self.geoPackageOverlays = [[GeoPackageMapOverlays alloc] initWithMapView: self.mapView];
}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (!polygonsAdded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.mapView addOverlays:[OfflineMapUtility getPolygons] level:MKOverlayLevelAboveRoads];
            polygonsAdded = YES;
        });
    }
    
    self.noLocationsView.hidden = NO;

    CLLocationCoordinate2D zoomLocation;
    zoomLocation.latitude = 40.740848;
    zoomLocation.longitude= -73.991145;
    
    NSMutableArray *notUserLocations = [NSMutableArray arrayWithArray:self.mapView.annotations];
    [notUserLocations removeObject:self.mapView.userLocation];
    [self.mapView removeAnnotations:notUserLocations];

    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(queue, ^{
        [self update];
    });
}

-(void) update{
    for (Report * report in self.reports) {
        // TODO: this check needs to be a null check or hasLocation or something else better
        if (report.lat != 0.0f && report.lon != 0.0f) {
            ReportMapAnnotation *annotation = [[ReportMapAnnotation alloc] initWithReport:report];
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self.mapView addAnnotation:(id)annotation];
            });
            self.noLocationsView.hidden = YES;
        }
    }
    
    [self.geoPackageOverlays updateMap];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark Map view delegate methods
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id)annotation
{
    
    if ([annotation isKindOfClass:[ReportMapAnnotation class]]) {
        static NSString *annotationIdentifier = @"ReportMapAnnotation";
        MKAnnotationView *annotationView = [mapView dequeueReusableAnnotationViewWithIdentifier:annotationIdentifier];
        ReportMapAnnotation *customAnnotation = annotation;
        
        if (!annotationView) {
            annotationView = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:annotationIdentifier];
            annotationView.canShowCallout = YES;
            annotationView.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        } else {
            annotationView.annotation = customAnnotation;
        }
        
        annotationView.image = [UIImage imageNamed:@"map-point"];
        return annotationView;
    }
    
    return nil;
}

- (MKOverlayRenderer *) mapView:(MKMapView *) mapView rendererForOverlay:(id < MKOverlay >) overlay {
    if ([overlay isKindOfClass:[MKTileOverlay class]]) {
        return [[MKTileOverlayRenderer alloc] initWithTileOverlay:overlay];
    } else if ([overlay isKindOfClass:[MKPolygon class]]) {
        
        MKPolygon *polygon = (MKPolygon *) overlay;
        MKPolygonRenderer *renderer = [[MKPolygonRenderer alloc] initWithPolygon:polygon];

        if ([overlay.title isEqualToString:@"ocean"]) {
            renderer.fillColor = [UIColor colorWithRed:127/255.0 green:153/255.0 blue:151/255.0 alpha:1.0];
            renderer.strokeColor = [UIColor clearColor];
            renderer.lineWidth = 0.0;
            //renderer.opaque = TRUE;
        }
        else if ([overlay.title isEqualToString:@"feature"]) {
            renderer.fillColor = [UIColor colorWithRed:221/255.0 green:221/255.0 blue:221/255.0 alpha:1.0];
            renderer.strokeColor = [UIColor clearColor];
            renderer.lineWidth = 0.0;
            //renderer.opaque = TRUE;
        }
        else {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSString *maptype = [defaults stringForKey:@"maptype"];
            if ([@"Offline" isEqual:maptype]) {
                renderer.fillColor = [[UIColor whiteColor] colorWithAlphaComponent:1.0];
            }
            else {
                renderer.fillColor = [[UIColor yellowColor] colorWithAlphaComponent:0.2];
            }
            renderer.lineWidth = 2;
            renderer.strokeColor = [UIColor orangeColor];
        }
        
        return renderer;
    } else if ([overlay isKindOfClass:[MKPolyline class]]) {
        MKPolyline *polyline = (MKPolyline *) overlay;
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:polyline];
        renderer.strokeColor = [UIColor blackColor];
        renderer.lineWidth = 1;
        return renderer;
    }
    
    return nil;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control
{
    _selectedReport = ((ReportMapAnnotation *)view.annotation).report;
    [self.delegate reportSelectedToView:_selectedReport];
}

@end
