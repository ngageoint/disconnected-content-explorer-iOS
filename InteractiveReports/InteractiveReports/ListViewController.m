//
//  ListViewController.m
//  InteractiveReports
//

#import "ListViewController.h"
#import "GlobeViewController.h"

@interface ListViewController ()

@end


@implementation ListViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateReport:) name:@"DICEReportUpdatedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnzipProgress:) name:@"DICEReportUnzipProgressNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleURLRequest:) name:@"DICEURLOpened" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reportsRefreshed:) name:@"DICEReportsRefreshed" object:nil];
    
    self.title = @"Disconnected Interactive Content Explorer";
    
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    // for pull to refresh
    self.tableViewController = [[UITableViewController alloc] init];
    self.tableViewController.tableView = self.tableView;
    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refreshControlValueChanged) forControlEvents:UIControlEventValueChanged];
    self.tableViewController.refreshControl = refreshControl;
}


- (void)refreshControlValueChanged
{
    [_tableViewController.refreshControl endRefreshing];
    [[ReportAPI sharedInstance] loadReports];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


# pragma mark - Notification handling methods
- (void)updateReport:(NSNotification *)notification
{
    Report *report = notification.userInfo[@"report"];
    NSLog(@"%@ %@ message recieved", notification, [report title]);
    [_tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
}


- (void)updateUnzipProgress:(NSNotification *)notification
{
    int index = [notification.userInfo[@"index"] intValue];
    Report *report = self.reports[index];
    report.totalNumberOfFiles = [notification.userInfo[@"totalNumberOfFiles"] intValue];
    report.progress = [notification.userInfo[@"progress"] intValue];
    [_tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
}


- (void)reportsRefreshed:(NSNotification *)notification
{
    [_tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
}

- (void)handleURLRequest:(NSNotification*)notification
{
    NSDictionary *urlParams = notification.userInfo;
    NSString *reportID = urlParams[@"reportID"];
    if (!reportID) {
        return;
    }
    [self.reports enumerateObjectsUsingBlock:^(Report *report, NSUInteger idx, BOOL *stop) {
        if ([report.reportID isEqualToString: reportID]) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:idx inSection:0];
            [_tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionMiddle];
        }
    }];
}


#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.reports.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    Report *report = self.reports[indexPath.row];
    UITableViewCell *cell;
    
    if ([report.fileExtension isEqualToString:@"pdf"]) {
        cell = [self.tableView dequeueReusableCellWithIdentifier:@"pdfCell" forIndexPath:indexPath];
    }
    else {
        cell = [self.tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    }
    
    if ([report.thumbnail isKindOfClass:[NSString class]]) {
        NSURL *thumbnailUrl = [NSURL URLWithString:report.thumbnail relativeToURL:report.url];
        UIImage *image = [UIImage imageWithContentsOfFile:thumbnailUrl.path];
        CGSize itemSize = CGSizeMake(70, 70);
        UIGraphicsBeginImageContext(itemSize);
        CGRect imageRect = CGRectMake(0.0, 0.0, itemSize.width, itemSize.height);
        [image drawInRect:imageRect];
        cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    else {
        cell.imageView.image = [UIImage imageNamed:@"dice-default"];
    }
    
    if (report.isEnabled) {
        cell.userInteractionEnabled = cell.textLabel.enabled = cell.detailTextLabel.enabled = YES;
        cell.detailTextLabel.text = report.description;
    }
    else if (report.error != nil) {
        cell.userInteractionEnabled = cell.textLabel.enabled = cell.detailTextLabel.enabled = NO;
        cell.detailTextLabel.text = report.error;
        cell.imageView.image = [UIImage imageNamed:@"dice-error"];
    }
    else {
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
        [self.reports removeObjectAtIndex:indexPath.row];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
    else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
    }
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    self.selectedCell = [self.tableView cellForRowAtIndexPath:indexPath];
    [self.delegate reportSelectedToView:self.reports[indexPath.row]];
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

@end
