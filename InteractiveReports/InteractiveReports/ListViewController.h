//
//  ListViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "ReportViewController.h"
#import "TileViewController.h"
#import "MapViewController.h"
#import "PDFViewController.h"
#import "ReportAPI.h"
#import "Report.h"


@class ListViewController;

@interface ListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate> {}

@property (strong, nonatomic) UITableViewCell *selectedCell;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) UITableViewController *tableViewController;
@property (strong, nonatomic) IBOutlet UITableView *tableView;

@end
