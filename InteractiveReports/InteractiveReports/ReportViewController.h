//
//  ReportViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "Report.h"
#import "NoteViewController.h"

@interface ReportViewController : UIViewController <UISplitViewControllerDelegate, UIScrollViewDelegate>

@property (strong, nonatomic) IBOutlet UIWebView *webView;
@property (strong, nonatomic) NSString *reportPath;
@property (strong, nonatomic) NSString *reportName;
@property (strong, nonatomic) NSString *reportFormat;
@property (strong, nonatomic) IBOutlet UINavigationItem *navBar;
@property (strong, nonatomic) Report *report;
@property (strong, nonatomic) UILabel *unzipStatusLabel;
@property (nonatomic) BOOL singleReport;
@property (nonatomic) BOOL unzipComplete;

@end
