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


@implementation JavaScriptAPI

- (id)initWithWebView:(UIWebView *)webView report:(Report *)report andDelegate:(NSObject<UIWebViewDelegate> *)delegate
{
    if ((self = [super init])) {
        self.webview = webView;
        self.webViewDelegate = delegate;
        self.report = report;
        NSLog(@"Bridge created.");
        
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
            responseCallback([self geolocate]);
        }];
        
        [self.bridge registerHandler:@"click" handler:^(id data, WVJBResponseCallback responseCallback) {
            NSLog(@"Bridge recieved request to query on a map click: %@", data);
            responseCallback([self click:data]);
        }];
        
        [self.bridge send:@"Hello Javascript" responseCallback:^(id responseData) {
            NSLog(@"Objective C got a response!!!");
        }];
        
        self.locationManager = [[CLLocationManager alloc] init];
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        self.locationManager.delegate = self;
        
    }
    
    return self;
}


- (void)sendToBridge:(NSDictionary*)message
{
    [self.bridge send:message];
}


- (NSDictionary *)exportJSON:(id)data
{
    if (data) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsPath = [paths objectAtIndex:0]; //Get the docs directory
        
        NSFileManager *fm = [[NSFileManager alloc] init];
        NSError *error;
        
        BOOL isDir;
        BOOL exists = [fm fileExistsAtPath:[documentsPath stringByAppendingPathComponent:@"export"] isDirectory:&isDir];
        if (!exists) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[documentsPath stringByAppendingPathComponent:@"export"] withIntermediateDirectories:NO attributes:nil error:&error];
        }
        
        NSString *filePath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"/export/%@_export.json", self.report.title]]; //Add the file name
        NSDictionary *dataDict = (NSDictionary*)data;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dataDict options:0 error:&error];
        NSString *jsonString = [[NSString alloc] initWithBytes:[jsonData bytes] length:[jsonData length] encoding:NSUTF8StringEncoding];
        if (error != nil) {
            NSLog(@"Error creating NSDictionary: %@", [error localizedDescription]);
            return @{ @"success": @NO, @"message": @"Unable to parse JSON."};
        } else {
            [jsonString writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
            if (error == nil) {
                
                [[NSNotificationCenter defaultCenter]
                 postNotificationName:[JavaScriptNotification geoJSONExported] object:self
                 userInfo:@{
                            @"filePath": filePath
                            }];

                
                return @{ @"success": @YES, @"message": @"Sucessfully wrote file"};
            } else {
                return @{ @"success": @NO, @"message": [error localizedDescription]};
            }
        }
    }
    
    return @{ @"success": @NO, @"message": @"Null data was sent to the Javascript Bridge."};
}


- (NSDictionary *)geolocate
{
    [self configureLocationServices];
    if (self.locationManager.location != nil) {
        NSString *lat = [[NSString alloc] initWithFormat:@"%f", self.locationManager.location.coordinate.latitude];
        NSString *lon = [[NSString alloc] initWithFormat:@"%f", self.locationManager.location.coordinate.longitude];
        return @{@"success": @YES, @"lat": lat,  @"lon": lon};
    }
    
    return @{ @"success": @NO, @"message": @"Unable to access location manager, check your device settings."};
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
- (void)configureLocationServices
{
    if ([CLLocationManager locationServicesEnabled]) {
        if ([self.locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
            [self.locationManager requestWhenInUseAuthorization];
        } else {
            [self startUpdatingLocation];
        }
    }
}


-(void)startUpdatingLocation
{
    [self.locationManager startUpdatingLocation];
    [self.locationManager stopUpdatingLocation];
}


#pragma mark - CLLocationManager delegate methods
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        [self startUpdatingLocation];
    }
}


@end

