//
//  CollectionViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "Report.h"
#import "ReportViewController.h"
#import "MapViewController.h"
#import "ReportViewCell.h"

@interface TileViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate>

@property (strong, nonatomic) ReportViewController *reportViewController;
@property (strong, nonatomic) NSMutableArray *reports;
@property (strong, nonatomic) UITableViewCell *selectedCell;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) IBOutlet UICollectionView *tileView;

@end
