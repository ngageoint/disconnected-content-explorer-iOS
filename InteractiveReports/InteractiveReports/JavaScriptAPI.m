//
//  JavaScriptAPI.m
//  InteractiveReports
//

#import "JavaScriptAPI.h"

@implementation JavaScriptAPI

WebViewJavascriptBridge *bridge;

- (id)initWithWebView:(UIWebView *)webView report:(Report *)report andDelegate:(NSObject<UIWebViewDelegate> *)delegate
{
    if ((self = [super init])) {
        self.webview = webView;
        self.report = report;
        NSLog(@"Bridge created.");
        
        bridge = [WebViewJavascriptBridge bridgeForWebView:self.webview webViewDelegate:delegate handler:^(id data, WVJBResponseCallback responseCallback) {
            NSLog(@"Objective C reieved a message from JS: %@", data);
            responseCallback(@"Response for message from Objective C");
        }];
        
        [bridge registerHandler:@"saveToFile" handler:^(id data, WVJBResponseCallback responseCallback) {
            NSLog(@"Test objective c callback called: %@", data);
            responseCallback([self exportJSON:data]);
        }];
        
        [bridge send:@"Hello Javascript" responseCallback:^(id responseData) {
            NSLog(@"Objective C got a response!!!");
        }];
    }
    
    return self;
}


- (void)sendToBridge:(NSString*)string
{
    [bridge send:string];
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
            return @{ @"success": @"false", @"message": @"Unable to parse JSON."};
        } else {
            [jsonString writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
            if (error == nil) {
                return @{ @"success": @"true", @"message": @"Sucessfully wrote File"};
            } else {
                return @{ @"success": @"false", @"message": [error localizedDescription]};
            }
        }
    }
    
    return @{ @"success": @"false", @"message": @"Null data was sent to the Javascript Bridge."};
}


- (void)geolocate:(id)data withCallback:(WVJBResponseCallback)responseCallback
{
    // use LocationManager to get the users location
    // hand it back with the callback
}

@end
