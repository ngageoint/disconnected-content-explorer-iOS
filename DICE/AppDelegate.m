//
//  AppDelegate.m
//  InteractiveReports
//


#import "AppDelegate.h"
#import "DICENavigationController.h"
#import "OfflineMapUtility.h"
#import "ReportStore.h"
#import "GPKGGeoPackageValidate.h"
#import "GPKGGeoPackageFactory.h"
#import "DICEConstants.h"
#import "DICEDefaultArchiveFactory.h"
#import "DICEDownloadManager.h"
#import "DICEUtiExpert.h"
#import "GeoPackageURLProtocol.h"
#import "HtmlReportType.h"

@interface AppDelegate ()

@property (readonly, weak, nonatomic) DICENavigationController *navigation;
@property (readonly, nonatomic) DICEDownloadManager *downloadManager;

@end


@implementation AppDelegate

- (DICENavigationController *)navigation
{
    return (DICENavigationController *)self.window.rootViewController;
}


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSLog(@"app finished launching with options:\n%@", launchOptions);

    NSPredicate *excludeGeopackageDir = [NSPredicate predicateWithFormat:@"self.lastPathComponent like %@", @"geopackage"];
    NSArray *exclusions = @[excludeGeopackageDir];

    DICEUtiExpert *utiExpert = [[DICEUtiExpert alloc] init];
    id<DICEArchiveFactory> archiveFactory = [[DICEDefaultArchiveFactory alloc] initWithUtiExpert:utiExpert];
    NSOperationQueue *importQueue = [[NSOperationQueue alloc] init];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSNotificationCenter *notificationCenter = NSNotificationCenter.defaultCenter;
    NSURL *reportsDir = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL];

    ReportStore *store = [[ReportStore alloc] initWithReportsDir:reportsDir exclusions:exclusions utiExpert:utiExpert archiveFactory:archiveFactory importQueue:importQueue fileManager:fileManager notifications:notificationCenter application:application];
    ReportStore.sharedInstance = store;

    _downloadManager = [[DICEDownloadManager alloc] initWithDownloadDir:reportsDir fileManager:fileManager delegate:store];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"dice.download"];
    configuration.sessionSendsLaunchEvents = YES;
    configuration.discretionary = YES;
    _downloadManager.downloadSession = [NSURLSession sessionWithConfiguration:configuration delegate:_downloadManager delegateQueue:importQueue];
    store.downloadManager = _downloadManager;

    store.reportTypes = @[
        [[HtmlReportType alloc] initWithFileManager:store.fileManager]
    ];

    // initialize offline map polygons
    // TODO: potentially thread this
    // TODO: change to geopackage
    NSDictionary *geojson = [OfflineMapUtility dictionaryWithContentsOfJSONString:@"ne_50m-110m_land"];
    NSMutableArray *featuresArray = geojson[@"features"];
    [OfflineMapUtility generateExteriorPolygons:featuresArray];
    
    [GeoPackageURLProtocol start];
    
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive.
    // If the application was previously in the background, optionally refresh the user interface.
    NSLog(@"app became active");
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    NSLog(@"app resigning active");
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    NSLog(@"app will enter foreground");
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    NSLog(@"app did enter background");
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
        NSString * fileUrl = [url path];
        
        // Handle GeoPackage files
        if ([GPKGGeoPackageValidate hasGeoPackageExtension:fileUrl]) {
            // Import the GeoPackage file
            NSString * name = [[fileUrl lastPathComponent] stringByDeletingPathExtension];
            if ([self importGeoPackageFile:fileUrl withName:name]) {
                // Set the new GeoPackage as active
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                NSMutableDictionary * selectedCaches = [[defaults objectForKey:DICE_SELECTED_CACHES] mutableCopy];
                if(selectedCaches == nil){
                    selectedCaches = [[NSMutableDictionary alloc] init];
                }
                [selectedCaches setObject:[[NSMutableArray alloc] init] forKey:name];
                [defaults setObject:selectedCaches forKey:DICE_SELECTED_CACHES];
                [defaults setObject:nil forKey:DICE_SELECTED_CACHES_UPDATED];
                [defaults synchronize];
            }
        }
        else {
            // TODO: figure if/how to restore this functionality
            // another app's UIDocumentInteractionController wants to use DICE to open a file
//            [[ReportStore sharedInstance] attemptToImportReportFromResource:url afterImport:^(Report *report) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    [self.navigation navigateToReport:report childResource:nil animated:NO];
//                });
//            }];
            [[ReportStore sharedInstance] attemptToImportReportFromResource:url];
        }
    }
    else {
        // some other app opened DICE directly, let's see what they want to do
        [self.navigation navigateToReportForURL:url fromApp:sourceApplication];
    }
    
    return YES;
}

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)())completionHandler
{
    if ([identifier isEqualToString:@"dice.download"]) {
        [_downloadManager handleEventsForBackgroundURLSession:identifier completionHandler:completionHandler];
    }
}

- (BOOL)importGeoPackageFile:(NSString *)path withName:(NSString *)name
{
    // Import the GeoPackage file
    BOOL imported = false;
    GPKGGeoPackageManager * manager = [GPKGGeoPackageFactory getManager];
    @try {
        imported = [manager importGeoPackageFromPath:path withName:name andOverride:true andMove:true];
    }
    @finally {
        [manager close];
    }
    
    if(!imported){
        NSLog(@"Error importing GeoPackage file: %@, name: %@", path, name);
    }
    
    return imported;
}

@end
