//
//  CollectionViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "Report.h"
#import "ReportCollectionView.h"
#import "ReportViewCell.h"

@interface TileViewController : UIViewController <ReportCollectionView, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate, UIActionSheetDelegate>

@property (strong, nonatomic) NSArray *reports;
@property (strong, nonatomic) id<ReportCollectionViewDelegate> delegate;
@property (strong, nonatomic) UITableViewCell *selectedCell;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) IBOutlet UICollectionView *tileView;
@property (strong, nonatomic) UIRefreshControl *refreshControl;
@property (nullable, nonatomic) Report *actionReport;

@end
