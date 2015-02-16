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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshReportTiles:) name:[ReportNotification reportUpdated] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateReportImportProgress:) name:[ReportNotification reportImportProgress] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshReportTiles:) name:[ReportNotification reportsLoaded] object:nil];
    
    [self.tileView setDataSource:self];
    [self.tileView setDelegate:self];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
        cell.reportDescription.text = report.description;
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
        [_tileView reloadData];
    });
}


- (void)updateReportImportProgress:(NSNotification *)notification
{
    // Check for the placeholder report, and remove it if is present.
    for (int i = 0; i < [self.reports count]; i++) {
        if ([[[self.reports objectAtIndex:i] reportID] isEqualToString:[ReportAPI userGuideReportID]]) {
            [self.reports removeObjectAtIndex:i];
            break;
        }
    }
    
    
    Report *notificationReport = notification.userInfo[@"report"];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        //TODO: change this up to take the loop out, passing the index from the API gives inconsistant results
        for (int i = 0; i < [self.reports count]; i++) {
            if ([[self.reports objectAtIndex:i] sourceFile] == [notificationReport sourceFile]) {
                [self.reports replaceObjectAtIndex:i withObject:notificationReport];
                break;
            }
        }
        
        //[_tileView.refreshControl endRefreshing];
        [_tileView reloadData];
    });
}

@end
