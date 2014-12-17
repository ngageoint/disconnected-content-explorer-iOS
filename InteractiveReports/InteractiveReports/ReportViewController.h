//
//  ReportViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "Report.h"


@interface ReportViewController : UIViewController <UISplitViewControllerDelegate, UIScrollViewDelegate>

@property (strong, nonatomic) IBOutlet UIWebView *webView;
@property (strong, nonatomic) IBOutlet UINavigationItem *navBar;

@property (strong, nonatomic) Report *report;
@property (strong, nonatomic) UILabel *unzipStatusLabel;

@end
