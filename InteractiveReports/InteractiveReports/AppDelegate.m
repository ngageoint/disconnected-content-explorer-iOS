//
//  AppDelegate.m
//  InteractiveReports
//


#import "AppDelegate.h"

@interface AppDelegate ()

@property (nonatomic, strong) NSString *srcScheme;
@property (nonatomic, strong) NSString *reportID;

@end


@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    _srcScheme = nil;
    _reportID = nil;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearSrcScheme:) name:@"DICEClearSrcScheme" object:nil];
    
    //initializing offline map polygons (potentially thread this)
    NSDictionary *geojson = [OfflineMapUtility dictionaryWithContentsOfJSONString:@"ne_50m_land.simplify0.2"];
    NSMutableArray *featuresArray = [geojson objectForKey:@"features"];
    [OfflineMapUtility generateExteriorPolygons:featuresArray];
    
    return YES;
}


- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    self.didBecomeActive = YES;
    
    ListViewController *listView = (ListViewController *)self.window.rootViewController;
    listView.didBecomeActive = YES;
}


- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if (!url) {
        return NO;
    }
    
    NSString *URLString = [url absoluteString];
    NSLog(@"Here is the URL DICE got called with: %@ by %@", URLString, sourceApplication);
    
    NSArray *parameters = [[url query] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"=&"]];
    _urlParameters = [NSMutableDictionary dictionary];
    
    for (int i = 0; i < [parameters count]; i=i+2) {
        NSLog(@"Key: %@ Value: %@", [parameters objectAtIndex:i], [parameters objectAtIndex:i+1]);
        [_urlParameters setObject:[parameters objectAtIndex:i+1] forKey:[parameters objectAtIndex:i]];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEURLOpened"
                                                        object:nil
                                                      userInfo:_urlParameters];
    
    return YES;
}


- (void)clearSrcScheme:(NSNotification*)notification
{
    _srcScheme = @"";
}

@end
