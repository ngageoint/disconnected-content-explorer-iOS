//
//  ReportViewController.m
//  InteractiveReports
//


#import "ReportViewController.h"
#import "ResourceTypes.h"

@interface ReportViewController () <UIWebViewDelegate> {
}

@property (weak, nonatomic) IBOutlet UIToolbar *toolbar;
@property CGFloat scrollOffset;
@property BOOL hidingToolbar;

@property (strong, nonatomic) UIPopoverController *masterPopoverController;
- (void)configureView;
@end


@implementation ReportViewController

#pragma mark - Managing the detail item
- (void)setDetailItem:(id)newDetailItem
{
    if (_detailItem != newDetailItem) {
        _detailItem = newDetailItem;
        
        // Update the view.
        [self configureView];
    }
    
    if (self.masterPopoverController != nil) {
        [self.masterPopoverController dismissPopoverAnimated:YES];
    }
}


- (void)configureView
{
    // Update the user interface for the detail item.
}


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
    
    if (![self.report.fileExtension isEqualToString:@"pdf"])
        [self loadReportContent];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleNotification:) name:@"DICEReportUpdatedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnzipProgress:) name:@"DICEReportUnzipProgressNotification" object:nil];
    
    _unzipStatusLabel = [[UILabel alloc] init];
    _unzipComplete = NO;
    
    _srcURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://?srcScheme=dice", self.srcScheme]];
    NSString *aKey;
    NSEnumerator *keyEnumerator = [_urlParams keyEnumerator];
    while (aKey = [keyEnumerator nextObject]) {
        if ([aKey isEqualToString:@"srcScheme"]) {} // do nothing if they passed in a srcScheme, since once they navigate back to their app, DICE would be the src, as we set above
        else {
            _srcURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@&%@=%@", _srcURL, aKey, _urlParams[aKey]]];
        }
    }
    if ([self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
        // iOS 7
        [self performSelector:@selector(setNeedsStatusBarAppearanceUpdate)];
    } else {
        // iOS 6
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    }
    _toolbar.translucent = YES;
    
    _webView.scrollView.contentInset = UIEdgeInsetsMake(self.toolbar.frame.size.height, 0, 0, 0);
    _webView.scrollView.backgroundColor = [UIColor clearColor];
    _webView.backgroundColor = [UIColor clearColor];
    _webView.scalesPageToFit = YES;
    
    _hidingToolbar = NO;
    [_webView.scrollView setDelegate:self];
    _webView.delegate = self;
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
        } else {
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
}


// Handle the source url scheme and navigating back to the app that called into DICE,
// then clear it out so if the user navigates back into DICE they arent jolted back into the report view.
- (IBAction)backButtonTapped:(id)sender
{
    if (self.srcScheme != nil && ![self.srcScheme isEqualToString:@""]) {
        [self dismissViewControllerAnimated:YES completion:nil];
        [[UIApplication sharedApplication] openURL:_srcURL];
    }
    else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    
    self.srcScheme = @"";
    // TODO: handle this in app delegate and get rid of all the observers for this notification
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DICEClearSrcScheme" object:nil];
}


# pragma mark - notification handling methods
- (void)handleNotification:(NSNotification *)notification
{
    if (self.singleReport) {
        NSLog(@"DetailView: handling notification");
        [_unzipStatusLabel performSelectorOnMainThread:@selector(setText:) withObject:@"Loading..." waitUntilDone:NO];
        [_unzipStatusLabel removeFromSuperview];
        self.unzipComplete = YES;
        Report *report = notification.userInfo[@"report"];
        NSLog(@"%@ message recieved", [report title]);
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
            [self performSegueWithIdentifier:@"showLinkedResource" sender:self];
        }
        // TODO: add support for linked dice reports - maybe by dice:// url, or just an absolute url as opposed to relative to current report
        return NO;
    }
    return YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    if ([_webView isLoading]) {
        [_webView stopLoading];
    }
    _webView.delegate = nil;
}

@end
