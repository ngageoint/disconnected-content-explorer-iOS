//
//  AppDelegate.m
//  InteractiveReports
//


#import "AppDelegate.h"
#import "DICENavigationController.h"
#import "OfflineMapUtility.h"
#import "ReportAPI.h"

@interface AppDelegate ()

@property (readonly, weak, nonatomic) DICENavigationController *navigation;

@end


@implementation AppDelegate

- (DICENavigationController *)navigation
{
    return (DICENavigationController *)self.window.rootViewController;
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSLog(@"DICE finished launching with options:\n%@", launchOptions);
    
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
        // another app's UIDocumentInteractionController wants to use DICE to open a file
        [[ReportAPI sharedInstance] importReportFromUrl:url afterImport:^(Report *report) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.navigation navigateToReport:report childResource:nil animated:NO];
            });
        }];
    }
    else {
        // some other app opened DICE directly, let's see what they want to do
        [self.navigation navigateToReportForURL:url fromApp:sourceApplication];
    }
    
    return YES;
}

@end
