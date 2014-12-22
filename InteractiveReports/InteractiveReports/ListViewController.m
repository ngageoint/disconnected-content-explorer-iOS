//
//  ListViewController.m
//  InteractiveReports
//

#import "ReportAPI.h"
#import "ListViewController.h"

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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshReportList:) name:[ReportNotification reportUpdated] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshReportList:) name:[ReportNotification reportImportProgress] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshReportList:) name:[ReportNotification reportsLoaded] object:nil];
    
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
    [[ReportAPI sharedInstance] loadReports];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)refreshReportList:(NSNotification *)notification
{
    [_tableViewController.refreshControl endRefreshing];
    [_tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
}

// TODO: make a new notification to indicate the last selected report
// can probably handle setting the selection in viewWillAppear:animated:
// instead of with a notification
// we will probably need a report stack when we implement inter-linking
// reports, so we can just peek at the top of the stack to find the last
// selected report
- (void)handleURLRequest:(NSNotification*)notification
{
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
    [self.tableView deselectRowAtIndexPath:indexPath animated:NO];
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
