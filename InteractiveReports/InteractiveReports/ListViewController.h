//
//  ListViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "ReportViewController.h"
#import "TileViewController.h"
#import "MapViewController.h"
#import "ReportAPI.h"
#import "Report.h"


@class ListViewController;

@interface ListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate> {}

@property (strong, nonatomic) NSURL *unzippedIndexURL;
@property (strong, nonatomic) UITableViewCell *selectedCell;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) UITableViewController *tableViewController;
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) NSString *srcScheme;
@property (strong, nonatomic) NSString *reportID;
@property (strong, nonatomic) NSDictionary *urlParams;
@property (nonatomic) BOOL didBecomeActive;
@property (nonatomic) BOOL singleReportLoaded;
@property (weak, nonatomic) IBOutlet UISegmentedControl *segmentedControl;

- (void) gridButtonTapped;
- (void) mapButtonTapped;

+ (NSDictionary *) dictionaryWithContentsOfJSONString: (NSString *) filePath;

@end
