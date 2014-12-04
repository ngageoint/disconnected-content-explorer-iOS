//
//  ReportViewController.m
//  InteractiveReports
//

#import "ReportAPI.h"
#import "ReportViewController.h"
#import "ReportLinkedResourceViewController.h"
#import "ResourceTypes.h"

@interface ReportViewController () <UIWebViewDelegate>

@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property CGFloat scrollOffset;
@property BOOL hidingToolbar;
@property NSURL *linkedResource;
@property (strong, nonatomic) UIPopoverController *masterPopoverController;

@end


@implementation ReportViewController

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat scrollDifference = _scrollOffset - scrollView.contentOffset.y;
    CGFloat toolbarWillMoveTo = 0.0;
    toolbarWillMoveTo = self.toolbar.frame.origin.y+scrollDifference;
    if (-toolbarWillMoveTo > self.toolbar.frame.size.height ) {
        toolbarWillMoveTo = -self.toolbar.frame.size.height;
    } else if (toolbarWillMoveTo > 0.0 || -scrollView.contentOffset.y > self.toolbar.frame.size.height) {
        toolbarWillMoveTo = 0.0;
    }
    
    
    [UIView beginAnimations: @"moveField"context: nil];
    [UIView setAnimationDelegate: self];
    [UIView setAnimationDuration: 0.5];
    [UIView setAnimationCurve: UIViewAnimationCurveEaseInOut];
    self.toolbar.frame = CGRectMake(self.toolbar.frame.origin.x,
                                    toolbarWillMoveTo,
                                    self.toolbar.frame.size.width,
                                    self.toolbar.frame.size.height);
    [UIView commitAnimations];
    
    _scrollOffset = scrollView.contentOffset.y;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (![self.report.fileExtension isEqualToString:@"pdf"]) {
        [self loadReportContent];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reportUpdated:) name:[ReportNotification reportUpdated] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnzipProgress:) name:[ReportNotification reportImportProgress] object:nil];
    
    _unzipStatusLabel = [[UILabel alloc] init];
    _unzipComplete = NO;
    
    if ([self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
        // iOS 7
        [self performSelector:@selector(setNeedsStatusBarAppearanceUpdate)];
    } else {
        // iOS 6
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    }
    _toolbar.translucent = YES;
    
    _webView.delegate = self;
    _webView.scrollView.delegate = self;
    _webView.scrollView.contentInset = UIEdgeInsetsMake(self.toolbar.frame.size.height, 0, 0, 0);
    _webView.scrollView.backgroundColor = [UIColor clearColor];
    _webView.backgroundColor = [UIColor clearColor];
    _webView.scalesPageToFit = YES;
    
    _hidingToolbar = NO;
}


- (BOOL)prefersStatusBarHidden {
    return YES;
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (self.singleReport && !self.unzipComplete) {
        NSLog(@"DetailView: setting up status text");
        
        _unzipStatusLabel.text = @"Unzipping...";
        _unzipStatusLabel.textColor = [UIColor grayColor];
        _unzipStatusLabel.bounds = CGRectMake(0.0, 0.0, 200.0, 200.0);
        _unzipStatusLabel.center = self.webView.center;
        [self.webView addSubview:_unzipStatusLabel];
    }
    
    if ([self.report.fileExtension isEqualToString:@"pdf"])
        [self loadReportContent];

}


- (void)loadReportContent
{
    if (self.report != nil) {
        NSLog(@"DetailView: loading report content");
        if ( [self.report.fileExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame ) {
            @try {
                NSURL* indexUrl = [self.report.url URLByAppendingPathComponent: @"index.html"];
                [self.webView loadRequest: [NSURLRequest requestWithURL:indexUrl]];
            }
            @catch (NSException *exception) {
                NSLog(@"Problem loading URL %@. Report name: %@", [exception reason], self.reportName);
            }
        }
        else {
            NSURL *url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@", self.report.url, self.report.title]];
            [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }
    _navBar.title = self.reportName;
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"showReportNotes"]) {
        NoteViewController *noteViewController = (NoteViewController *)segue.destinationViewController;
        noteViewController.report = self.report;
    }
    else if ([segue.identifier isEqualToString:@"showLinkedResource"]) {
        ReportLinkedResourceViewController *resourceViewer = (ReportLinkedResourceViewController *)segue.destinationViewController;
        resourceViewer.resource = self.linkedResource;
        self.linkedResource = nil;
    }
}


# pragma mark - notification handling methods
- (void)reportUpdated:(NSNotification *)notification
{
    if (self.singleReport) {
        [_unzipStatusLabel performSelectorOnMainThread:@selector(setText:) withObject:@"Loading..." waitUntilDone:NO];
        [_unzipStatusLabel removeFromSuperview];
        self.unzipComplete = YES;
        Report *report = notification.userInfo[@"report"];
        self.report = report;
        [self loadReportContent];
    }
}


- (void)updateUnzipProgress:(NSNotification *)notification
{
    if (self.singleReport) {
        [_unzipStatusLabel performSelectorOnMainThread:@selector(setText:) withObject:[NSString stringWithFormat:@"%@ of %@ unzipped", notification.userInfo[@"progress"], notification.userInfo[@"totalNumberOfFiles"]] waitUntilDone:NO];
    }
}


- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if (navigationType == UIWebViewNavigationTypeLinkClicked && request.URL.isFileURL) {
        if ([ResourceTypes canOpenResource:request.URL]) {
            self.linkedResource = request.URL;
            [self performSegueWithIdentifier:@"showLinkedResource" sender:self];
        }
        // TODO: add support for linked dice reports - maybe by dice:// url, or just an absolute url as opposed to relative to current report
        return NO;
    }
    return YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
    if ([_webView isLoading]) {
        [_webView stopLoading];
    }
}

@end
