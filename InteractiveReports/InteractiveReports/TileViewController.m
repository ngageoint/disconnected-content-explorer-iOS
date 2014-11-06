//
//  CollectionViewController.m
//  InteractiveReports
//

#import "TileViewController.h"

@interface TileViewController ()

@end

@implementation TileViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.reportCollectionView setDataSource:self];
    [self.reportCollectionView setDelegate:self];
    
    self.segmentedControl.selectedSegmentIndex = 1;
    [self.segmentedControl addTarget:self action:@selector(segmentButtonTapped:) forControlEvents:UIControlEventValueChanged];
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
    return _reports.count;
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    ReportViewCell *cell = [self.reportCollectionView dequeueReusableCellWithReuseIdentifier:@"reportCell" forIndexPath:indexPath];
    
    Report *report = _reports[indexPath.item];
    
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


- (void) segmentButtonTapped:(UISegmentedControl*)sender
{
    switch ([sender selectedSegmentIndex]) {
        case 0:
            [self performSegueWithIdentifier:@"tileToList" sender:self];
            break;
        case 1:
            break;
        case 2:
            [self performSegueWithIdentifier:@"tileToMap" sender:self];
            break;
    }
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"showDetail"]) {
        NSIndexPath *selectedIndexPath = [[self.reportCollectionView indexPathsForSelectedItems] objectAtIndex:0];
        ReportViewController *reportViewController = (ReportViewController *)segue.destinationViewController;
        reportViewController.report = [self.reports objectAtIndex:selectedIndexPath.row];
    } else if ([[segue identifier] isEqualToString:@"tileToMap"]) {
        MapViewController *mapViewController = (MapViewController *)segue.destinationViewController;
        mapViewController.reports = self.reports;
    }
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
    [self.reportCollectionView performBatchUpdates:nil completion:nil];
}

@end
