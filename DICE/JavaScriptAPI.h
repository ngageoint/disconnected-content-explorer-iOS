//
//  JavaScriptAPI.h
//  InteractiveReports
//
//  Created by Tyler Burgett on 1/16/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "WebViewJavascriptBridge.h"
#import "Report.h"


/**
 This class provides static methods that return strings for notification names that
 JavascriptAPI can produce.
 */
@interface JavaScriptNotification : NSObject 
/**
 This notification indicates that the geoJSON the user 
 wanted to export the JavaScript bridge is ready to be
 sent to an email view to be shipped off of the device.
 The NSNotification object userInfo dicationary contains
 {
    @"report": (Report*) the added report object,
    @"filePath": (NSString*) the path to the exported geoJSON
 }
 */
+ (NSString *)geoJSONExported;
@end


@interface JavaScriptAPI : NSObject <CLLocationManagerDelegate>

@property (strong, nonatomic)UIWebView *webview;
@property (strong, nonatomic)NSObject<UIWebViewDelegate> *webViewDelegate;
@property (strong, nonatomic)Report* report;
@property (strong, nonatomic)CLLocationManager *locationManager;
@property (strong, nonatomic)WebViewJavascriptBridge *bridge;

- (id)initWithWebView:(UIWebView *)webView report:(Report *)report andDelegate:(NSObject<UIWebViewDelegate> *)delegate;
- (void)sendToBridge:(NSString*)string;

@end
