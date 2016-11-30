//
//  ReportCollectionViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/18/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "ReportCollectionViewController.h"

#import "ReportStore.h"
#import "ReportCollectionView.h"
#import "ReportResourceViewController.h"


@interface ReportCollectionViewController () <ReportCollectionViewDelegate, NSURLConnectionDataDelegate>

@property (weak, nonatomic) IBOutlet UISegmentedControl *viewSegments;
@property (weak, nonatomic) IBOutlet UIView *collectionSubview;

- (IBAction)viewChanged:(UISegmentedControl *)sender;

@end


@implementation ReportCollectionViewController
{
    const NSArray *views;
    NSInteger currentViewIndex;
    NSArray *reports;
    Report *selectedReport;
    NSURL *pasteboardURL;
    NSHTTPURLResponse *pasteboardURLResponse;
    NSString *recentPasteboardURLKey;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        views = @[
            [self.storyboard instantiateViewControllerWithIdentifier: @"listCollectionView"],
            [self.storyboard instantiateViewControllerWithIdentifier: @"tileCollectionView"],
            [self.storyboard instantiateViewControllerWithIdentifier: @"mapCollectionView"]
        ];
    }
    else {
        views = @[
            [self.storyboard instantiateViewControllerWithIdentifier: @"tileCollectionView"],
            [self.storyboard instantiateViewControllerWithIdentifier: @"mapCollectionView"]
        ];
    }
    
    [views enumerateObjectsUsingBlock:^(UIViewController<ReportCollectionView> *view, NSUInteger idx, BOOL *stop) {
        view.delegate = self;
        view.reports = [[ReportStore sharedInstance] reports];
        view.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    }];
    
    UIViewController<ReportCollectionViewDelegate> *firstView = views.firstObject;
    [self addChildViewController: firstView];
    [firstView didMoveToParentViewController: self];
    firstView.view.frame = self.collectionSubview.bounds;
    [self.collectionSubview addSubview: firstView.view];
    recentPasteboardURLKey = @"RECENT_PASTEBOARD_URL_KEY";
    
    [[ReportStore sharedInstance] loadReports];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkPasteboardForReport) name:UIApplicationDidBecomeActiveNotification object:nil];
}


- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self checkPasteboardForReport];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"showReport"]) {
        ReportResourceViewController *reportViewController = (ReportResourceViewController *)segue.destinationViewController;
        reportViewController.report = selectedReport;
        reportViewController.resource = selectedReport.rootResource;
    }
}


- (IBAction)viewChanged:(UISegmentedControl *)sender
{
    UIViewController *current = views[currentViewIndex];
    UIViewController *target = views[sender.selectedSegmentIndex];
    CGRect currentFrame = self.collectionSubview.bounds;
    CGAffineTransform slide = CGAffineTransformMakeTranslation(-currentFrame.size.width, 0.0);
    CGRect startFrame = CGRectMake(currentFrame.size.width, currentFrame.origin.y, currentFrame.size.width, currentFrame.size.height);
    
    if (sender.selectedSegmentIndex < currentViewIndex) {
        startFrame.origin.x *= -1;
        slide.tx *= -1;
    }

    target.view.frame = startFrame;
    
    [current willMoveToParentViewController:nil];
    [self addChildViewController:target];
    
    [self transitionFromViewController:current toViewController:target duration:0.25 options:0
            animations:^{
                target.view.frame = currentFrame;
                current.view.frame = CGRectApplyAffineTransform(currentFrame, slide);
            }
            completion:^(BOOL finished) {
                [current removeFromParentViewController];
                [target didMoveToParentViewController:self];
                currentViewIndex = sender.selectedSegmentIndex;
            }];
}

- (void)reportSelectedToView:(Report *)report
{
    selectedReport = report;
//    if ([selectedReport.reportID isEqualToString:[ReportStore userGuideReportID]]) {
//        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/ngageoint/disconnected-content-explorer-examples/raw/master/reportzips/DICEUserGuide.zip"]];
//    }
//    else {
        [self performSegueWithIdentifier:@"showReport" sender:self];
//    }
}


- (void)checkPasteboardForReport
{
    NSLog(@"checking pasteboard contents ...");

    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    // TODO: does this call work on iOS < 10?
    if (!pasteboard.hasStrings) {
        return;
    }

    NSString *pasteboardString = pasteboard.string;

    NSLog(@"found pasteboard string: %@", pasteboardString);

    pasteboardURL = [NSURL URLWithString:pasteboardString];
    NSString *recentURL = [NSUserDefaults.standardUserDefaults stringForKey:recentPasteboardURLKey];

    if ([pasteboardURL.absoluteString isEqualToString:recentURL] || !(pasteboardURL && pasteboardURL.scheme && pasteboardURL.host)) {
        return;
    }

    // Before even giving the user the option to download, make sure that the link points to something we can use.
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:pasteboardURL];
    [request setHTTPMethod:@"HEAD"];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [NSURLConnection sendAsynchronousRequest:request queue:[[NSOperationQueue alloc] init]
        completionHandler:^(NSURLResponse *_Nullable response, NSData *_Nullable data, NSError *_Nullable connectionError) {
            NSString *mimeType = response.MIMEType;
            if ([@"application/zip" isEqualToString:mimeType] || [@"application/octet-stream" isEqualToString:mimeType]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Download?" message:pasteboardString preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *downloadAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
                        [NSUserDefaults.standardUserDefaults setObject:pasteboardURL.absoluteString forKey:recentPasteboardURLKey];
                        [ReportStore.sharedInstance attemptToImportReportFromResource:pasteboardURL];
                    }];

                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_Nonnull action) {
                        [NSUserDefaults.standardUserDefaults setObject:pasteboardURL.absoluteString forKey:recentPasteboardURLKey];
                    }];

                    [alertController addAction:cancelAction];
                    [alertController addAction:downloadAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                });
            }
        }];
#pragma clang diagnostic pop

}


- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
