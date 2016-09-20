//
//  ReportViewController.m
//  InteractiveReports
//

#import "HTMLViewController.h"

#import "ReportStore.h"
#import "NoteViewController.h"
#import "ReportResourceViewController.h"
#import "ResourceTypes.h"
#import "JavaScriptAPI.h"
#import "WebViewJavascriptBridge.h"

@interface HTMLViewController () <UIWebViewDelegate, UIDocumentInteractionControllerDelegate>
{
    UIDocumentInteractionController *docController;
}

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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reportImportFinished:) name:[ReportNotification reportImportFinished] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateUnzipProgress:) name:[ReportNotification reportExtractProgress] object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(emailDataExport:) name:[JavaScriptNotification geoJSONExported] object:nil];
    
    _unzipStatusLabel = [[UILabel alloc] init];
    
    if (self && [self respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) {
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
    [super viewWillAppear:animated];

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


#pragma mark - notification handling methods
- (void)reportImportFinished:(NSNotification *)notification
{
    Report *report = notification.userInfo[@"report"];
    if (report == self.report && self.report.isEnabled) {
        [_unzipStatusLabel performSelectorOnMainThread:@selector(setText:) withObject:@"Loading..." waitUntilDone:NO];
        [_unzipStatusLabel removeFromSuperview];
        [self loadReportContent];
    }
}


-(void)emailDataExport:(NSNotification *)notification
{
    if (![MFMailComposeViewController canSendMail]) {
        return;
    }
    MFMailComposeViewController *mailController = [[MFMailComposeViewController alloc] init];
    mailController.mailComposeDelegate = self;
    [mailController setSubject:[NSString stringWithFormat: @"%@ export", self.report.title]];
    
    NSString *filePath = notification.userInfo[@"filePath"];
    NSString *fileName = [NSString stringWithFormat:@"%@_export.json", self.report.title];
    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    
    [mailController addAttachmentData:fileData mimeType:@"application/json" fileName:fileName];
    [self presentViewController:mailController animated:YES completion:nil];
}


- (void)updateUnzipProgress:(NSNotification *)notification
{
    [_unzipStatusLabel performSelectorOnMainThread:@selector(setText:) withObject:[NSString stringWithFormat:@"%@%% extracted", notification.userInfo[@"percentExtracted"]] waitUntilDone:NO];
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
        else { // see if iOS knows about an installed app that can handle this file
            NSURL *url = request.URL;
            docController = [self setupControllerWithURL:url usingDelegate:self];
            [docController presentOpenInMenuFromRect:CGRectZero inView:self.view animated:YES];
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

    [super viewWillDisappear:animated];
}


- (void) mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error
{
    switch (result)
    {
        case MFMailComposeResultCancelled:
            NSLog(@"Mail cancelled");
            break;
        case MFMailComposeResultSaved:
            NSLog(@"Mail saved");
            break;
        case MFMailComposeResultSent:
            NSLog(@"Mail sent");
            break;
        case MFMailComposeResultFailed:
            NSLog(@"Mail sent failure: %@", [error localizedDescription]);
            break;
        default:
            break;
    }
    
    // Close the Mail Interface
    [self dismissViewControllerAnimated:YES completion:NULL];
}


- (UIDocumentInteractionController*) setupControllerWithURL:(NSURL*)fileURL usingDelegate:(id<UIDocumentInteractionControllerDelegate>)interactionDelegate
{
    UIDocumentInteractionController *interactionController = [UIDocumentInteractionController interactionControllerWithURL:fileURL];
    interactionController.delegate = interactionDelegate;
    return interactionController;
}

@end
