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
    NSLog(@"DICE became active");
}


- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if (!url) {
        return NO;
    }
    
    NSLog(@"open url request for %@ from app %@", url.absoluteString, sourceApplication);
    
    // TODO: present progress ui to offer choice go back to requesting app
    // or view the report when finished, e.g., when downloading reports from Safari
    
    if (url.isFileURL) {
        [[ReportAPI sharedInstance] importReportFromUrl:url afterImport:nil];
    }
    else {
        // some other app opened DICE, lets see what they want to do
        NSArray *parameters = [url.query componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"=&"]];
        NSMutableDictionary *urlParameters = [NSMutableDictionary dictionary];
        
        for (int keyIndex = 0; keyIndex < [parameters count]; keyIndex += 2) {
            NSString *key = parameters[keyIndex];
            NSString *value = parameters[keyIndex + 1];
            NSLog(@"Key: %@ Value: %@", key, value);
            [urlParameters setObject:value forKey:key];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEURLOpened"
                                                            object:nil
                                                          userInfo:urlParameters];
    }
    
    return YES;
}

@end
