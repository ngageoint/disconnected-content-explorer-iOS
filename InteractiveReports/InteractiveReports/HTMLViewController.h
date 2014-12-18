//
//  ReportViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>

#import "ResourceTypes.h"


@interface HTMLViewController : UIViewController <ResourceHandler, UISplitViewControllerDelegate, UIScrollViewDelegate>

@property (strong, nonatomic) IBOutlet UIWebView *webView;
@property (strong, nonatomic) IBOutlet UINavigationItem *navBar;

@end
