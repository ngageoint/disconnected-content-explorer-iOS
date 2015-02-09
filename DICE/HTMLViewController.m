//
//  ReportViewController.m
//  InteractiveReports
//

#import "HTMLViewController.h"

#import "ReportAPI.h"
#import "NoteViewController.h"
#import "ReportResourceViewController.h"
#import "ResourceTypes.h"
#import "JavaScriptAPI.h"
#import "WebViewJavascriptBridge.h"

@interface HTMLViewController () <UIWebViewDelegate>

@property (strong, nonatomic) UILabel *unzipStatusLabel;

@property (strong, nonatomic) Report *report;
@property (strong, nonatomic) NSURL *reportResource;
@property (strong, nonatomic) JavaScriptAPI *javascriptAPI;
//@property WebViewJavascriptBridge *bridge;

@end


@implementation HTMLViewController

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{

}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reportUpdated:) name:[ReportNotification reportUpdated] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnzipProgress:) name:[ReportNotification reportImportProgress] object:nil];
    
    _unzipStatusLabel = [[UILabel alloc] init];
    
    if ([self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
        // iOS 7
        [self performSelector:@selector(setNeedsStatusBarAppearanceUpdate)];
    }
    else {
        // iOS 6
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationSlide];
    }
    
    _webView.delegate = self;
    _webView.scrollView.delegate = self;
    _webView.scrollView.backgroundColor = [UIColor clearColor];
    _webView.backgroundColor = [UIColor clearColor];
    _webView.scalesPageToFit = YES;
}


- (BOOL)prefersStatusBarHidden
{
    return YES;
}


- (void)viewWillAppear:(BOOL)animated
{
    _javascriptAPI = [[JavaScriptAPI alloc] initWithWebView:_webView report:_report andDelegate:self];
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (!self.report.isEnabled) {
        _unzipStatusLabel.text = @"Loading...";
        _unzipStatusLabel.textColor = [UIColor grayColor];
        _unzipStatusLabel.bounds = CGRectMake(0.0, 0.0, 200.0, 200.0);
        _unzipStatusLabel.center = self.webView.center;
        [self.webView addSubview:_unzipStatusLabel];
    }
}


- (void)handleResource:(NSURL *)resource forReport:(Report *)report
{
    self.report = report;
    self.reportResource = resource;
    [self loadReportContent];
}


- (void)loadReportContent
{
    @try {
        NSLog(@"HTMLViewController loading url %@ (base: %@)", self.reportResource, self.reportResource.baseURL);
        [self.webView loadRequest:[NSURLRequest requestWithURL:self.reportResource]];
    }
    @catch (NSException *exception) {
        NSLog(@"Problem loading URL %@. Report name: %@", exception.reason, self.report.title);
    }
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


#pragma mark - notification handling methods
- (void)reportUpdated:(NSNotification *)notification
{
    Report *report = notification.userInfo[@"report"];
    if (report == self.report && self.report.isEnabled) {
        [_unzipStatusLabel performSelectorOnMainThread:@selector(setText:) withObject:@"Loading..." waitUntilDone:NO];
        [_unzipStatusLabel removeFromSuperview];
        [self loadReportContent];
    }
}


- (void)updateUnzipProgress:(NSNotification *)notification
{
    [_unzipStatusLabel performSelectorOnMainThread:@selector(setText:) withObject:[NSString stringWithFormat:@"%@ of %@ unzipped", notification.userInfo[@"progress"], notification.userInfo[@"totalNumberOfFiles"]] waitUntilDone:NO];
}


- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if (navigationType == UIWebViewNavigationTypeLinkClicked && request.URL.isFileURL) {
        if ([ResourceTypes canOpenResource:request.URL]) {
            // TODO: better api for url handling, e.g., dice://reports/{reportID}/relative_resource?options
            NSString *base = self.report.url.baseURL.absoluteString;
            NSString *relativeResource = [request.URL.absoluteString substringFromIndex:base.length];
            NSURL *diceURL = [NSURL URLWithString:[NSString stringWithFormat:@"dice://?reportID=%@&resource=%@", self.report.reportID, relativeResource]];
            [[UIApplication sharedApplication] openURL:diceURL];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
