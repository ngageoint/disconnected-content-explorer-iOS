//
//  CollectionViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "Report.h"
#import "ReportCollectionView.h"
#import "ReportViewCell.h"

@interface TileViewController : UIViewController <ReportCollectionView, UICollectionViewDataSource, UICollectionViewDelegate>

@property (strong, nonatomic) NSArray *reports;
@property (strong, nonatomic) id<ReportCollectionViewDelegate> delegate;
@property (strong, nonatomic) UITableViewCell *selectedCell;
@property (strong, nonatomic) UIActivityIndicatorView *spinner;
@property (strong, nonatomic) IBOutlet UICollectionView *tileView;

@end
