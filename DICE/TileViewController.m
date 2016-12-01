//
//  CollectionViewController.m
//  InteractiveReports
//

#import "TileViewController.h"
#import "ReportStore.h"

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
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateReportImportProgress:) name:ReportNotification.reportExtractProgress object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateReportImportProgress:) name:ReportNotification.reportDownloadProgress object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateReportImportProgress:) name:ReportNotification.reportDownloadComplete object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshReportTiles:) name:ReportNotification.reportImportFinished object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshReportTiles:) name:ReportNotification.reportAdded object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshReportTiles:) name:ReportNotification.reportRemoved object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshReportTiles:) name:ReportNotification.reportsLoaded object:nil];

    [self.tileView setDataSource:self];
    [self.tileView setDelegate:self];
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshControlValueChanged) forControlEvents:UIControlEventValueChanged];
    [self.tileView addSubview:self.refreshControl];
    self.tileView.alwaysBounceVertical = YES;
    
    UILongPressGestureRecognizer *gestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    gestureRecognizer.delegate = self;
    gestureRecognizer.delaysTouchesBegan = YES;
    [self.tileView addGestureRecognizer:gestureRecognizer];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
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
    [[ReportStore sharedInstance] loadReports];
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

    cell.userInteractionEnabled = report.isEnabled;
    cell.reportTitle.text = report.title;
    cell.reportTitle.editable = NO;
    cell.reportTitle.userInteractionEnabled = NO;
    cell.reportDescription.text = report.summary;
    cell.reportDescription.editable = NO;
    cell.reportDescription.userInteractionEnabled = NO;
    cell.reportImage.image = [UIImage imageNamed:@"dice-default"];

    if (!report.isImportFinished) {
        return cell;
    }

    if (report.importStatus == ReportImportStatusFailed) {
        cell.reportImage.image = [UIImage imageNamed:@"dice-error"];
        return cell;
    }

    NSString *thumbnailPath = nil;
    if (report.baseDir) {
        if (report.tileThumbnail.length > 0) {
            thumbnailPath = [report.baseDir.path stringByAppendingPathComponent:report.tileThumbnail];
        }
        else if (report.thumbnail.length > 0) {
            thumbnailPath = [report.baseDir.path stringByAppendingPathComponent:report.thumbnail];
        }
    }
    
    if (thumbnailPath) {
        UIImage *image = [UIImage imageWithContentsOfFile:thumbnailPath];
        cell.reportImage.image = image;
    }

    return cell;
}


- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout  *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *deviceType = [UIDevice currentDevice].model;
    
    if([deviceType isEqualToString:@"iPhone"]) {
        return CGSizeMake(collectionView.bounds.size.width, 160.0);
    }
    
    // Adjust cell size for orientation
    if (UIInterfaceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation])) {
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


-(void)handleLongPress:(UILongPressGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state != UIGestureRecognizerStateEnded) {
        return;
    }
    
    NSIndexPath *indexPath = [self.tileView indexPathForItemAtPoint:[gestureRecognizer locationInView:self.tileView]];
    
    if (indexPath == nil) {
        return;
    }

    Report *report = self.reports[indexPath.item];
    self.actionReport = report;
    NSString *title = [NSString stringWithFormat:@"Delete %@?", self.actionReport.title];
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Delete", nil];

    [actionSheet showInView:self.view];
}


- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"Delete"]) {
        [[ReportStore sharedInstance] deleteReport:self.actionReport];
    }
}


@end
