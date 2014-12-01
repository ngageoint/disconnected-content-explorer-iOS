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
    //initializing offline map polygons (potentially thread this)
    NSDictionary *geojson = [OfflineMapUtility dictionaryWithContentsOfJSONString:@"ne_50m_land.simplify0.2"];
    NSMutableArray *featuresArray = [geojson objectForKey:@"features"];
    [OfflineMapUtility generateExteriorPolygons:featuresArray];
    
    return YES;
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive.
    // If the application was previously in the background, optionally refresh the user interface.
}


- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if (!url) {
        return NO;
    }
    
    NSString *URLString = [url absoluteString];
    NSLog(@"Here is the URL DICE got called with: %@ by %@", URLString, sourceApplication);
    
    if (sourceApplication == nil) {
        // an "open in" request with a file:// url
        // copy the file into the DICE report folder
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *filename = [url lastPathComponent];
        NSString *documentspath = [NSHomeDirectory() stringByAppendingString:@"/Documents/"];
        NSString *pathToCopyFrom = [NSString stringWithFormat:@"%@Inbox/%@", documentspath, filename];
        NSError *error;
        [fileManager copyItemAtPath:pathToCopyFrom toPath:[NSString stringWithFormat:@"%@%@", documentspath, filename] error:&error];
        
        if (error) {
            NSLog(@"Something bad happened %@", [error localizedDescription]);
        }
        
        _urlParameters = [NSMutableDictionary dictionary];
        [_urlParameters setObject:filename forKey:@"reportID"];
        
        // have the local report manager load the new file
        [[ReportAPI sharedInstance] loadReportsWithCompletionHandler:^{
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
        NSArray *parameters = [[url query] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"=&"]];
        _urlParameters = [NSMutableDictionary dictionary];
        
        for (int i = 0; i < [parameters count]; i=i+2) {
            NSLog(@"Key: %@ Value: %@", [parameters objectAtIndex:i], [parameters objectAtIndex:i+1]);
            [_urlParameters setObject:[parameters objectAtIndex:i+1] forKey:[parameters objectAtIndex:i]];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEURLOpened"
                                                            object:nil
                                                          userInfo:_urlParameters];
    }
    
    return YES;
}

@end
