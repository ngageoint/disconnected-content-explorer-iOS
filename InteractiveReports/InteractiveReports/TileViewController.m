//
//  CollectionViewController.m
//  InteractiveReports
//

#import "TileViewController.h"
#import "ReportAPI.h"

@interface TileViewController ()

@end


@implementation TileViewController

NSMutableArray* reports;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    reports = [[ReportAPI sharedInstance] getReports];
    
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
    return reports.count;
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    ReportViewCell *cell = [self.tileView dequeueReusableCellWithReuseIdentifier:@"reportCell" forIndexPath:indexPath];
    
    Report *report = reports[indexPath.item];
    
    if ( [report.tileThumbnail isKindOfClass:[NSString class]]) {
        NSString *thumbnailString = [NSString stringWithFormat:@"%@%@", report.url, report.tileThumbnail];
        UIImage *image = [UIImage imageWithContentsOfFile:thumbnailString];
        
        cell.reportImage.image = image;
    } else {
        cell.reportImage.image = [UIImage imageNamed:@"dice-default"];
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


- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self.tileView performBatchUpdates:nil completion:nil];
}

@end
