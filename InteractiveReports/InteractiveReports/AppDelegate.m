//
//  AppDelegate.m
//  InteractiveReports
//


#import "AppDelegate.h"
#import "OfflineMapUtility.h"
#import "ReportAPI.h"

@interface AppDelegate ()

@end


@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // initialize offline map polygons
    // TODO: potentially thread this
    NSDictionary *geojson = [OfflineMapUtility dictionaryWithContentsOfJSONString:@"ne_50m_land.simplify0.2"];
    NSMutableArray *featuresArray = [geojson objectForKey:@"features"];
    [OfflineMapUtility generateExteriorPolygons:featuresArray];
    
    return YES;
}


- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive.
    // If the application was previously in the background, optionally refresh the user interface.
}


- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if (!url) {
        return NO;
    }
    
    NSString *URLString = [url absoluteString];
    NSLog(@"open url request for %@ from app %@", URLString, sourceApplication);
    
    if (url.isFileURL) {
        // an "open in" request with a file:// url
        // move the file into the DICE report folder
        // TODO: move this file work to ReportAPI and do in background
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *documentsDir = [fileManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSString *fileName = url.lastPathComponent;
        NSURL *destFile = [documentsDir URLByAppendingPathComponent:fileName];
        NSError *error;
        
        [fileManager moveItemAtURL:url toURL:destFile error:&error];
        
        if (error) {
            NSLog(@"error moving file %@ to documents directory for open request: %@", url, [error localizedDescription]);
        }
        
        
        // TODO: present progress ui to offer choice go back to requesting app
        // or view the report when finished, e.g., when downloading reports from Safari
        
        _urlParameters = [NSMutableDictionary dictionary];
        [_urlParameters setObject:fileName forKey:@"reportID"];
        
        [[ReportAPI sharedInstance] loadReportsWithCompletionHandler:^{
            // TODO: ensure these notifications are on the main thread
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEReportsRefreshed"
                                                                object:nil
                                                              userInfo:nil];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEURLOpened"
                                                                object:nil
                                                              userInfo:_urlParameters];
        }];
        
    }
    else {
        // some other app opened DICE, lets see what they want to do
        NSArray *parameters = [url.query componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"=&"]];
        _urlParameters = [NSMutableDictionary dictionary];
        
        for (int keyIndex = 0; keyIndex < [parameters count]; keyIndex += 2) {
            NSString *key = parameters[keyIndex];
            NSString *value = parameters[keyIndex + 1];
            NSLog(@"Key: %@ Value: %@", key, value);
            [_urlParameters setObject:value forKey:key];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEURLOpened"
                                                            object:nil
                                                          userInfo:_urlParameters];
    }
    
    return YES;
}

@end
