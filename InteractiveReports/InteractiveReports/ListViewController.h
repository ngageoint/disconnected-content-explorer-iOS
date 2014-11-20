//
//  ListViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>

#import "Report.h"
#import "ReportAPI.h"
#import "ReportCollectionView.h"


@class ListViewController;

@interface ListViewController : UIViewController <ReportCollectionView, UITableViewDataSource, UITableViewDelegate> {}

@property (strong, nonatomic) NSMutableArray *reports;
@property (strong, nonatomic) id<ReportCollectionViewDelegate> delegate;
@property (strong, nonatomic) UITableViewCell *selectedCell;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) UITableViewController *tableViewController;
@property (strong, nonatomic) IBOutlet UITableView *tableView;

@end
