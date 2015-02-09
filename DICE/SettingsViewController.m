//
//  SettingsViewController.m
//  InteractiveReports
//
// The title of this class is a bit off at the moment, since it is just attribution and version info.
// Theme switcher, and default view settings coming soon(TM).
//

#import "SettingsViewController.h"

@interface SettingsViewController () <UIWebViewDelegate>

@property (weak, nonatomic) IBOutlet UILabel *versionLabel;
@property (weak, nonatomic) IBOutlet UIWebView *attributionsWebView;
@property (strong, nonatomic) IBOutletCollection(UIWebView) NSArray *attributionsWebViewGestures;

@end

@implementation SettingsViewController

// The values for version and build can be updated in the project plist.
- (void)viewDidLoad
{
    [super viewDidLoad];
    NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
    
    NSString *version = infoDictionary[@"CFBundleShortVersionString"];
    
    _versionLabel.text = [NSString stringWithFormat:@"Version %@", version];
    
    UISwipeGestureRecognizer *swipeBack = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(webViewBackGesture:)];
    swipeBack.direction = UISwipeGestureRecognizerDirectionRight;
    [_attributionsWebView addGestureRecognizer:swipeBack];
    _attributionsWebView.delegate = self;
    _attributionsWebView.scalesPageToFit = NO;
    _attributionsWebView.dataDetectorTypes = UIDataDetectorTypeLink;
    
    NSURL *attributionsResource = [[NSBundle mainBundle] URLForResource:@"attributions/index" withExtension:@"html"];
    [_attributionsWebView loadRequest:[NSURLRequest requestWithURL:attributionsResource]];
    
    self.preferredContentSize = CGSizeMake(480.0, 320.0);
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *url = request.URL;
    
    if (navigationType != UIWebViewNavigationTypeLinkClicked || url.isFileURL) {
        return YES;
    }
    
    [[UIApplication sharedApplication] openURL:url];
    return NO;
}

- (void)webViewBackGesture:(UIGestureRecognizer *)sender
{
    [_attributionsWebView goBack];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
