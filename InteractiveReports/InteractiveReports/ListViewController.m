//
//  ListViewController.m
//  InteractiveReports
//

#import "ListViewController.h"

@interface ListViewController () {
    NSMutableArray *reports;
}
@end


@implementation ListViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (void)awakeFromNib
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        //self.clearsSelectionOnViewWillAppear = NO;
    }
    [super awakeFromNib];
}


- (void)viewDidLoad
{
    NSLog(@"In list view, viewDidLoad");
    [super viewDidLoad];
    self.title = @"Disconnected Interactive Content Explorer";
    
    reports = [[NSMutableArray alloc] init];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    // for pull to refresh
    self.tableViewController = [[UITableViewController alloc] init];
    self.tableViewController.tableView = self.tableView;
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshControlValueChanged) forControlEvents:UIControlEventValueChanged];
    self.tableViewController.refreshControl = refreshControl;
    self.singleReportLoaded = false;
    
    [[ReportAPI sharedInstance] loadReports];
    reports = [[ReportAPI sharedInstance] getReports];
    
    [self.segmentedControl addTarget:self action:@selector(segmentButtonTapped:) forControlEvents:UIControlEventValueChanged];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateReport:) name:@"DICEReportUpdatedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnzipProgress:) name:@"DICEReportUnzipProgressNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleURLRequest:) name:@"DICEURLOpened" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearSrcScheme:) name:@"DICEClearSrcScheme" object:nil];
}


- (void) viewDidAppear:(BOOL)animated
{
    // Some special case stuff, if there is only one report, we may want to open it rather than present the list
    if (reports.count == 1) {
        // if we have a srcSchema, then another app called into DICE, open the report
        if((_srcScheme != nil && ![_srcScheme isEqualToString:@""])) {
            [self performSegueWithIdentifier:@"singleReport" sender:self];
        } else if (self.didBecomeActive) {
            [self performSegueWithIdentifier:@"singleReport" sender:self];
        }
        self.didBecomeActive = NO;
    }
}


- (void)refreshControlValueChanged
{
    [_tableViewController.refreshControl endRefreshing];
    [[ReportAPI sharedInstance] loadReports];
    reports = [[ReportAPI sharedInstance] getReports];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)insertNewObject:(id)sender
{
    if (!reports) {
        reports = [[NSMutableArray alloc] init];
    }
    [reports insertObject:[NSDate date] atIndex:0];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}



# pragma mark - Notification handling methods
- (void)updateReport:(NSNotification *)notification
{
    int index = [notification.userInfo[@"index"] intValue];
    Report *report = notification.userInfo[@"report"];
    
    NSLog(@"%@ message recieved", [report title]);
    [reports replaceObjectAtIndex:index withObject:report];
    [_tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
    if (reports.count == 1) {
        self.singleReportLoaded = YES;
    }
}


- (void)updateUnzipProgress:(NSNotification *)notification
{
    int index = [notification.userInfo[@"index"] intValue];
    
    Report *report = [reports objectAtIndex:index];
    report.totalNumberOfFiles = [notification.userInfo[@"totalNumberOfFiles"] intValue];
    report.progress = [notification.userInfo[@"progress"] intValue];
    [reports replaceObjectAtIndex:index withObject:report];
    [_tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
    if (reports.count == 1) {
        self.singleReportLoaded = YES;
    }
}


- (void)handleURLRequest:(NSNotification*)notification
{
    _urlParams = notification.userInfo;
    _srcScheme = _urlParams[@"srcScheme"];
    _reportID = _urlParams[@"reportID"];
    
    NSLog(@"URL parameters: srcScheme: %@ reportID: %@", _srcScheme, _reportID);
    
    if (_reportID) {
        for (int i = 0; i < [reports count]; i++) {
            if ([[[reports objectAtIndex:i] reportID] isEqualToString:_reportID]) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
                [_tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];
                [self performSegueWithIdentifier:@"showDetail" sender:self];
                break;
            }
        }
    }
}


- (void)clearSrcScheme:(NSNotification*)notification
{
    _srcScheme = @"";
    _didBecomeActive = NO;
}


#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return reports.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];

    Report *report = reports[indexPath.row];
    
    if ( [report.thumbnail isKindOfClass:[NSString class]]) {
        NSString *thumbnailString = [NSString stringWithFormat:@"%@%@", report.url, report.thumbnail];
        UIImage *image = [UIImage imageWithContentsOfFile:thumbnailString];
        
        CGSize itemSize = CGSizeMake(70, 70);
        UIGraphicsBeginImageContext(itemSize);
        CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
        [image drawInRect:imageRect];
        cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        //cell.imageView.image = image;
    } else {
        cell.imageView.image = [UIImage imageNamed:@"dice-default"];
    }
    
    if (report.isEnabled) {
        cell.userInteractionEnabled = cell.textLabel.enabled = cell.detailTextLabel.enabled = YES;
        cell.detailTextLabel.text = report.description;
    } else if (report.error != nil) {
        cell.userInteractionEnabled = cell.textLabel.enabled = cell.detailTextLabel.enabled = NO;
        cell.detailTextLabel.text = report.error;
        cell.imageView.image = [UIImage imageNamed:@"dice-error"];
    } else {
        cell.userInteractionEnabled = cell.textLabel.enabled = cell.detailTextLabel.enabled = NO;
        
        if (report.totalNumberOfFiles > 0 && report.progress > 0) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d of %d files unzipped", report.progress, report.totalNumberOfFiles ];
        }
    }
    
    cell.textLabel.text = report.title;
    
    return cell;
}


- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Return NO if you do not want the specified item to be editable.
    return YES;
}


- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [reports removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
    }
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    self.selectedCell = [self.tableView cellForRowAtIndexPath:indexPath];
}


// This disables table view row swipe to delete
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_tableView.editing)
    {
        return UITableViewCellEditingStyleDelete;
    }
    
    return UITableViewCellEditingStyleNone;
}


#pragma mark - toolbar button handling
- (void) gridButtonTapped
{
    [self performSegueWithIdentifier:@"tableToCollection" sender:self];
}


- (void) mapButtonTapped
{
    [self performSegueWithIdentifier:@"tableToMap" sender:self];
}


- (void) segmentButtonTapped:(UISegmentedControl*)sender
{
    switch ([sender selectedSegmentIndex]) {
        case 0:
            break;
        case 1:
            [self performSegueWithIdentifier:@"listToTile" sender:self];
            break;
        case 2:
            [self performSegueWithIdentifier:@"listToMap" sender:self];
            break;
    }
}


- (void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"showDetail"]) {
        ReportViewController *reportViewController = (ReportViewController *)segue.destinationViewController;
        NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
        reportViewController.report = [reports objectAtIndex:indexPath.row];
        
        if (_srcScheme) {
            reportViewController.srcScheme = _srcScheme;
            reportViewController.urlParams = _urlParams;
        }
    } else if ([[segue identifier] isEqualToString:@"listToTile"]) {
        TileViewController *collectionViewController = (TileViewController *)segue.destinationViewController;
        collectionViewController.reports = reports;
    } else if ([[segue identifier] isEqualToString:@"listToMap"]) {
        MapViewController *mapViewController = (MapViewController *)segue.destinationViewController;
        mapViewController.reports = reports;
    } else if ([[segue identifier] isEqualToString:@"singleReport"]) {
        ReportViewController *reportViewController = (ReportViewController *)segue.destinationViewController;
        reportViewController.srcScheme = _srcScheme;
        reportViewController.urlParams = _urlParams;
        reportViewController.report = [reports objectAtIndex:0];
        reportViewController.singleReport = YES;
        reportViewController.unzipComplete = _singleReportLoaded;
    }
}


+ (NSDictionary *) dictionaryWithContentsOfJSONString: (NSString *) filePath
{
    NSData *data = [NSData dataWithContentsOfFile: filePath];
    __autoreleasing NSError *error = nil;
    id result = [NSJSONSerialization JSONObjectWithData:data
                                                options:kNilOptions
                                                  error:&error];
    if (error != nil)
        return nil;
    
    return result;
}

@end
