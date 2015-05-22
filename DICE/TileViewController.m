//
//  CollectionViewController.m
//  InteractiveReports
//

#import "TileViewController.h"
#import "ReportAPI.h"

@interface TileViewController ()

@end


@implementation TileViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateReportImportProgress:) name:[ReportNotification reportImportProgress] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshReportTiles:) name:[ReportNotification reportImportFinished] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshReportTiles:) name:[ReportNotification reportsLoaded] object:nil];
    
    [self.tileView setDataSource:self];
    [self.tileView setDelegate:self];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshControlValueChanged) forControlEvents:UIControlEventValueChanged];
    [self.tileView addSubview:self.refreshControl];
    self.tileView.alwaysBounceVertical = YES;
}

- (void)viewWillAppear:(BOOL)animated
{
    // hack to get around iOS 7 bug that doesn't refresh the data seemingly if the view is not visible
    [self refreshReportTiles:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)refreshControlValueChanged
{
    [[ReportAPI sharedInstance] loadReports];
}



- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}


- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.reports.count;
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    ReportViewCell *cell = [self.tileView dequeueReusableCellWithReuseIdentifier:@"reportCell" forIndexPath:indexPath];
    cell.layer.shouldRasterize = YES;
    cell.layer.rasterizationScale = [UIScreen mainScreen].scale;
    
    Report *report = self.reports[indexPath.item];
    
    if ([report.tileThumbnail isKindOfClass:[NSString class]]) {
        NSURL *thumbnailUrl = [NSURL URLWithString:report.tileThumbnail relativeToURL:report.url];
        UIImage *image = [UIImage imageWithContentsOfFile:thumbnailUrl.path];
        cell.reportImage.image = image;
    }
    else {
        cell.reportImage.image = [UIImage imageNamed:@"dice-default"];
    }
    
    if (report.isEnabled) {
        cell.userInteractionEnabled = YES;
        cell.reportDescription.text = report.summary;
        [cell.reportDescription setEditable:NO];
        [cell.reportDescription setUserInteractionEnabled:NO];
    }
    else if (report.error != nil) {
        cell.userInteractionEnabled = NO;
        cell.reportDescription.text = report.error;
        cell.reportImage.image = [UIImage imageNamed:@"dice-error"];
    }
    else {
        cell.userInteractionEnabled = NO;
        if (report.totalNumberOfFiles > 0 && report.progress > 0) {
            cell.reportDescription.text = [NSString stringWithFormat:@"%d of %d files unzipped", report.progress, report.totalNumberOfFiles ];
        }
    }
    
    cell.reportTitle.text = report.title;
    [cell.reportTitle setEditable:NO];
    [cell.reportTitle setUserInteractionEnabled:NO];
    return cell;
}


- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout  *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *deviceType = [UIDevice currentDevice].model;
    
    if([deviceType isEqualToString:@"iPhone"]) {
        return CGSizeMake(collectionView.bounds.size.width, 160.0);
    }
    
    // Adjust cell size for orientation
    if (UIDeviceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation])) {
        return CGSizeMake(334.f, 240.f);
    }
    return CGSizeMake(243.f, 235.f);
}


- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    Report *report = self.reports[indexPath.item];
    [self.delegate reportSelectedToView:report];
}


- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self.tileView performBatchUpdates:nil completion:nil];
}


- (void)refreshReportTiles:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([notification.name isEqualToString:[ReportNotification reportsLoaded]]) {
            [self.refreshControl endRefreshing];
        }
        [self.tileView reloadData];
    });
}


- (void)updateReportImportProgress:(NSNotification *)notification
{
    [self refreshReportTiles:notification];
}

@end
