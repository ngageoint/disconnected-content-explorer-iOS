//
//  ReportViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import <MessageUI/MessageUI.h>

#import "ResourceTypes.h"


@interface HTMLViewController : UIViewController <ResourceHandler, UISplitViewControllerDelegate, UIScrollViewDelegate, MFMailComposeViewControllerDelegate>

@property (strong, nonatomic) IBOutlet UIWebView *webView;

@end
