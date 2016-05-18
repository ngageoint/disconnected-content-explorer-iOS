//
//  JavaScriptAPI.m
//  InteractiveReports
//

#import "JavaScriptAPI.h"
#import "GeoPackageURLProtocol.h"
#import "GPKGBoundingBox.h"


@implementation JavaScriptNotification
+ (NSString *)geoJSONExported {
    return @"DICE.geoJSONExported";
}
@end


@interface JavaScriptAPI ()

@end

@implementation JavaScriptAPI
{
    NSMutableArray *_geolocateCallbacks;
    CLAuthorizationStatus _geolocateAuth;
}

- (id)initWithWebView:(UIWebView *)webView report:(Report *)report andDelegate:(NSObject<UIWebViewDelegate> *)delegate
{
    if (!(self = [super init])) {
        return nil;
    }

    _geolocateCallbacks = [NSMutableArray array];
    _geolocateAuth = [CLLocationManager authorizationStatus];

    self.report = report;
    self.webview = webView;
    self.webViewDelegate = delegate;

    self.bridge = [WebViewJavascriptBridge bridgeForWebView:self.webview webViewDelegate:self.webViewDelegate handler:^(id data, WVJBResponseCallback responseCallback) {
        NSLog(@"Objective C reieved a message from JS: %@", data);
        responseCallback(@"Response for message from Objective C");
    }];

    [self.bridge registerHandler:@"saveToFile" handler:^(id data, WVJBResponseCallback responseCallback) {
        NSLog(@"Bridge recieved request to export data: %@", data);
        responseCallback([self exportJSON:data]);
    }];

    [self.bridge registerHandler:@"getLocation" handler:^(id data, WVJBResponseCallback responseCallback) {
        NSLog(@"Bridge recieved request to geolocate: %@", data);
        [self geolocateWithCallback:responseCallback];
    }];

    [self.bridge registerHandler:@"click" handler:^(id data, WVJBResponseCallback responseCallback) {
        NSLog(@"Bridge recieved request to query on a map click: %@", data);
        responseCallback([self click:data]);
    }];

    [self.bridge send:@"Hello Javascript" responseCallback:^(id responseData) {
        NSLog(@"Objective C got a response!!!");
    }];

    return self;
}


- (void)sendToBridge:(NSDictionary*)message
{
    [self.bridge send:message];
}


- (NSDictionary *)exportJSON:(NSDictionary *)data
{
    if (!data) {
        return @{ @"success": @NO, @"message": @"No data to export"};
    }

    NSError *error;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *documentsDir = [fm URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:&error];
    NSURL *exportDir = [documentsDir URLByAppendingPathComponent:@"export" isDirectory:YES];

    if (![fm createDirectoryAtURL:exportDir withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"error creating export directory: %@", error ? error.localizedDescription : @"no error description available");
        return @{ @"success": @NO, @"message": @"Failed to create directory for export" };
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];

    if (error != nil) {
        NSLog(@"error serializing dictionary to json: %@", [error localizedDescription]);
        return @{ @"success": @NO, @"message": [NSString stringWithFormat:@"Error creating data for export: %@", error.localizedDescription] };
    }

    NSString *exportFileName = [NSString stringWithFormat:@"%@_export.json", self.report.title];
    NSURL *exportFile = [exportDir URLByAppendingPathComponent:exportFileName isDirectory:NO];
    [jsonData writeToURL:exportFile options:0 error:&error];

    if (error != nil) {
        NSLog(@"error writing json data to file %@: %@", exportFile.path, error.localizedDescription);
        return @{ @"success": @NO, @"message": @"Error saving file" };
    }

    [[NSNotificationCenter defaultCenter]
        postNotificationName:[JavaScriptNotification geoJSONExported]
        object:self
        userInfo:@{
            @"filePath": exportFile.path
        }];

    return @{ @"success": @YES, @"message": @"Export successful - use iTunes to retrieve the exports directory from DICE."};
}


- (void)geolocateWithCallback:(WVJBResponseCallback)callback
{
    if (!self.locationManager.location) {
        if (![self configureLocationServices]) {
            callback(@{ @"success":@NO, @"message":@"DICE cannot access your location.  Please check your device settings." });
            return;
        }
    }

    [_geolocateCallbacks addObject:callback];
    [self flushGeolocateCallbacks];
}


- (void)flushGeolocateCallbacks
{
    CLLocation *loc = self.locationManager.location;

    if (!loc || _geolocateCallbacks.count == 0) {
        return;
    }

    NSString *lat = [[NSString alloc] initWithFormat:@"%f", loc.coordinate.latitude];
    NSString *lon = [[NSString alloc] initWithFormat:@"%f", loc.coordinate.longitude];
    NSDictionary *response = @{
        @"success": @YES,
        @"lat": lat,  @"lon": lon,
        // same keys as html5 geolocation Position object
        @"timestamp": [NSNumber numberWithDouble:loc.timestamp.timeIntervalSince1970],
        @"coords": @{
            @"latitude": [NSNumber numberWithDouble:loc.coordinate.latitude],
            @"longitude": [NSNumber numberWithDouble:loc.coordinate.longitude],
            @"altitude": [NSNumber numberWithDouble:loc.altitude],
            @"heading": [NSNumber numberWithDouble:loc.course],
            @"speed": [NSNumber numberWithDouble:loc.speed],
            @"accuracy": [NSNumber numberWithDouble:loc.horizontalAccuracy],
            @"altitudeAccuracy": [NSNumber numberWithDouble:loc.verticalAccuracy]
        }
    };

    dispatch_async(dispatch_get_main_queue(), ^{
        while (_geolocateCallbacks.count > 0) {
            WVJBResponseCallback callback = _geolocateCallbacks.firstObject;
            [_geolocateCallbacks removeObjectAtIndex:0];
            callback(response);
        }
    });
}


- (NSDictionary *)click:(id)data
{
    if (data) {
        NSDictionary *dataDict = (NSDictionary*)data;
        NSString * lat = [dataDict objectForKey:@"lat"];
        NSString * lon = [dataDict objectForKey:@"lng"];
        NSString * zoom = [dataDict objectForKey:@"zoom"];
        NSDictionary * bounds = [dataDict objectForKey:@"bounds"];
        if(lat != nil && lon != nil && zoom != nil && bounds != nil){

            CLLocationCoordinate2D location = CLLocationCoordinate2DMake([lat doubleValue], [lon doubleValue]);

            GPKGBoundingBox * mapBounds = nil;
            NSDictionary * southWest = [bounds objectForKey:@"_southWest"];
            NSDictionary * northEast = [bounds objectForKey:@"_northEast"];
            if(southWest != nil && northEast != nil){
                NSString * minLon = [southWest objectForKey:@"lng"];
                NSString * maxLon = [northEast objectForKey:@"lng"];
                NSString * minLat = [southWest objectForKey:@"lat"];
                NSString * maxLat = [northEast objectForKey:@"lat"];
                mapBounds = [[GPKGBoundingBox alloc] initWithMinLongitudeDouble:[minLon doubleValue] andMaxLongitudeDouble:[maxLon doubleValue] andMinLatitudeDouble:[minLat doubleValue]  andMaxLatitudeDouble:[maxLat doubleValue]];
            }

            if(mapBounds != nil){

                // Include points by default
                NSString * points = [dataDict objectForKey:@"points"];
                BOOL includePoints = (points == nil || [points boolValue]);

                // Do not include geometries by default
                NSString * geometries = [dataDict objectForKey:@"geometries"];
                BOOL includeGeometries = (geometries != nil && [geometries boolValue]);

                NSDictionary * clickData = [GeoPackageURLProtocol mapClickTableDataWithLocationCoordinate:location andZoom:[zoom doubleValue] andMapBounds:mapBounds andPoints:includePoints andGeometries:includeGeometries];

                if(clickData == nil){
                    return @{ @"success": @YES, @"message": @""};
                }

                NSError *error;
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:clickData options:0 error:&error];
                NSString *jsonString = [[NSString alloc] initWithBytes:[jsonData bytes] length:[jsonData length] encoding:NSUTF8StringEncoding];
                if (error != nil) {
                    NSLog(@"Error creating map click JSON response: %@", [error localizedDescription]);
                    return @{ @"success": @NO, @"message": @"Unable to parse JSON."};
                } else {
                    return @{ @"success": @YES, @"message": jsonString};
                }
            }else{
                return @{ @"success": @NO, @"message": @"Data bounds did not contain correct _southWest and _northWest values"};
            }
        }else{
            return @{ @"success": @NO, @"message": @"Data did not contain a lat, lng, zoom, and bounds value"};
        }
    }
    return @{ @"success": @NO, @"message": @"Null data was sent to the Javascript Bridge."};
}


// Location service checking to handle iOS 7 and 8
- (BOOL)configureLocationServices
{
    if ([self geolocationDisabled]) {
        return NO;
    }

    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 10.0;

    if (_geolocateAuth != kCLAuthorizationStatusAuthorizedWhenInUse && [self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
        [self.locationManager requestWhenInUseAuthorization];
    }

    return YES;
}


- (BOOL)geolocationDisabled
{
    if (![CLLocationManager locationServicesEnabled]) {
        return YES;
    }

    return _geolocateAuth == kCLAuthorizationStatusDenied || _geolocateAuth == kCLAuthorizationStatusRestricted;
}


#pragma mark - CLLocationManager delegate methods
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    _geolocateAuth = status;
    [self.locationManager stopUpdatingLocation];
    if (_geolocateCallbacks.count) {
        [self.locationManager startUpdatingLocation];
    }
}


- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    [self flushGeolocateCallbacks];
}


@end

