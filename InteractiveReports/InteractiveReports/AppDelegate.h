//
//  AppDelegate.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "ListViewController.h"
#import "OfflineMapUtility.h"
#import "ReportAPI.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate> {}

@property (strong, nonatomic) UIWindow *window;
@property (strong, nonatomic) NSMutableDictionary *urlParameters;
@property (nonatomic) BOOL didBecomeActive;

@end
