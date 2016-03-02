//
//  MapViewController.m
//  InteractiveReports
//

#import "MapViewController.h"
#import "GeoPackageMapOverlays.h"
#import "DICEConstants.h"

#define METERS_PER_MILE = 1609.344

@interface MapViewController ()

@property (weak, nonatomic) IBOutlet UIView *noLocationsView;
@property (nonatomic, strong) GeoPackageMapOverlays * geoPackageOverlays;
@property (nonatomic, strong) NSMutableArray<ReportMapAnnotation *> * reportAnnotations;

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
    self.reportAnnotations = [[NSMutableArray alloc] init];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mapTap:)];
    [self.mapView addGestureRecognizer:tap];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:DICE_ZOOM_TO_REPORTS];
    [defaults synchronize];
}


- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (!polygonsAdded) {
        [self.mapView addOverlays:[OfflineMapUtility getPolygons] level:MKOverlayLevelAboveRoads];
        polygonsAdded = YES;
    }
    
    [self update];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults addObserver:self
               forKeyPath:DICE_SELECTED_CACHES_UPDATED
                  options:NSKeyValueObservingOptionNew
                  context:NULL];
}

- (void) viewWillDisappear:(BOOL)animated {
    
    [super viewWillDisappear:animated];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObserver:self forKeyPath:DICE_SELECTED_CACHES_UPDATED];
}

-(void) observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if ([DICE_SELECTED_CACHES_UPDATED isEqualToString:keyPath]) {
        dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
        dispatch_async(queue, ^{
            [self.geoPackageOverlays updateMap];
        });
    }
}

-(void) update{
    
    self.noLocationsView.hidden = NO;
    
    [self.mapView removeAnnotations:self.reportAnnotations];
    [self.reportAnnotations removeAllObjects];
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(queue, ^{
    
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        BOOL zoom = [defaults boolForKey:DICE_ZOOM_TO_REPORTS];
        if(zoom){
            [defaults setBool:NO forKey:DICE_ZOOM_TO_REPORTS];
            [defaults synchronize];
        }
        
        MKMapRect zoomRect = MKMapRectNull;
        
        for (Report * report in self.reports) {
            // TODO: this check needs to be a null check or hasLocation or something else better
            if (report.lat != 0.0f && report.lon != 0.0f) {
                ReportMapAnnotation *annotation = [[ReportMapAnnotation alloc] initWithReport:report];
                [self.reportAnnotations addObject:annotation];
                
                if(zoom){
                    MKMapPoint mapPoint = MKMapPointForCoordinate(annotation.coordinate);
                    MKMapRect pointRect = MKMapRectMake(mapPoint.x, mapPoint.y, 0.1, 0.1);
                    if (MKMapRectIsNull(zoomRect)) {
                        zoomRect = pointRect;
                    } else {
                        zoomRect = MKMapRectUnion(zoomRect, pointRect);
                    }
                }
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    [self.mapView addAnnotation:(id)annotation];
                });
                if(!self.noLocationsView.hidden){
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        self.noLocationsView.hidden = YES;
                    });
                }
            }
        }
        
        // Zoom to the reports
        if (!MKMapRectIsNull(zoomRect)) {
            float widthPadding = self.mapView.frame.size.width * .1;
            float heightPadding = self.mapView.frame.size.height * .1;
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self.mapView setVisibleMapRect:zoomRect edgePadding:UIEdgeInsetsMake(heightPadding, widthPadding, heightPadding, widthPadding) animated:YES];
            });
        }
        
        [self.geoPackageOverlays updateMap];
        
    });
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
        }
        else if ([overlay.title isEqualToString:@"feature"]) {
            renderer.fillColor = [UIColor colorWithRed:221/255.0 green:221/255.0 blue:221/255.0 alpha:1.0];
            renderer.strokeColor = [UIColor clearColor];
            renderer.lineWidth = 0.0;
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
        renderer.strokeColor = [UIColor orangeColor];
        renderer.lineWidth = 2;
        return renderer;
    }
    
    return nil;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control
{
    _selectedReport = ((ReportMapAnnotation *)view.annotation).report;
    [self.delegate reportSelectedToView:_selectedReport];
}

-(void)mapTap:(UIGestureRecognizer*)gesture {
    UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gesture;
    if (tap.state == UIGestureRecognizerStateEnded) {
        CGPoint tapPoint = [tap locationInView:self.mapView];
        CLLocationCoordinate2D tapCoord = [self.mapView convertPoint:tapPoint toCoordinateFromView:self.mapView];
        
        NSString * clickMessage = [self.geoPackageOverlays onMapClickWithLocationCoordinate:tapCoord andMap:self.mapView];
        if(clickMessage != nil){
            UIAlertController *alert = [UIAlertController
                                        alertControllerWithTitle:nil
                                        message:clickMessage
                                        preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* ok = [UIAlertAction
                                 actionWithTitle:@"OK"
                                 style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction * action)
                                 {
                                     [alert dismissViewControllerAnimated:YES completion:nil];
                                     
                                 }];
            [alert addAction:ok];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

@end
