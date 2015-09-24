//
//  JavaScriptAPI.m
//  InteractiveReports
//

#import "JavaScriptAPI.h"

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

    return @{ @"success": @YES, @"message": @"Export successful"};
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

