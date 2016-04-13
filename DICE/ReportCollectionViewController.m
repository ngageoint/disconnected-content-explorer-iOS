//
//  ReportCollectionViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/18/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "ReportCollectionViewController.h"

#import "ReportAPI.h"
#import "ReportCollectionView.h"
#import "ReportResourceViewController.h"


@interface ReportCollectionViewController () <ReportCollectionViewDelegate, UIActionSheetDelegate, NSURLConnectionDataDelegate>

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
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSLog(@"ReportCollectionViewController: loading report collection views");

    NSLog(@"%@", [UIDevice currentDevice].model);
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
        view.reports = [[ReportAPI sharedInstance] getReports];
        view.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    }];
    
    UIViewController<ReportCollectionViewDelegate> *firstView = views.firstObject;
    [self addChildViewController: firstView];
    [firstView didMoveToParentViewController: self];
    firstView.view.frame = self.collectionSubview.bounds;
    [self.collectionSubview addSubview: firstView.view];
    
    [[ReportAPI sharedInstance] loadReports];
}


- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    if (pasteboard.string) {
        NSLog(@"Checking pasteboard contents... %@", pasteboard.string);
        
        pasteboardURL = [NSURL URLWithString: pasteboard.string];
        if (pasteboardURL && pasteboardURL.scheme && pasteboardURL.host) {
            // Before even giving the user the option to download, make sure that the link points to something we can use.
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:pasteboardURL];
            [request setHTTPMethod:@"HEAD"];
            NSError *error = nil;
            NSHTTPURLResponse *response = nil;
            [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            
            NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
            [connection start];
            
        }
    }
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"showReport"]) {
        ReportResourceViewController *reportViewController = (ReportResourceViewController *)segue.destinationViewController;
        reportViewController.report = selectedReport;
        reportViewController.resource = selectedReport.url;
    }
}


- (IBAction)viewChanged:(UISegmentedControl *)sender {
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
    
    [self transitionFromViewController: current toViewController: target duration: 0.25 options: 0
            animations: ^{
                target.view.frame = currentFrame;
                current.view.frame = CGRectApplyAffineTransform(currentFrame, slide);
            }
            completion: ^(BOOL finished) {
                [current removeFromParentViewController];
                [target didMoveToParentViewController: self];
                currentViewIndex = sender.selectedSegmentIndex;
            }];
}

- (void)reportSelectedToView:(Report *)report {
    selectedReport = report;
    if ([selectedReport.reportID isEqualToString:[ReportAPI userGuideReportID]]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/ngageoint/disconnected-content-explorer-examples/raw/master/reportzips/DICEUserGuide.zip"]];
    }
    else {
        [self performSegueWithIdentifier:@"showReport" sender:self];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - Action Sheet delegate methods
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSLog(@"The %@ button was tapped.", [actionSheet buttonTitleAtIndex:buttonIndex]);
    
    if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"Download"]) {
        NSLog(@"Download tapped");
        // make the call to the ReportAPI
        [[ReportAPI sharedInstance] downloadReportAtURL:pasteboardURL];
    }
}


#pragma mark - NSURLConnectionDelegate

-(void)connection:(NSURLConnection *)connection didReceiveResponse:(nonnull NSURLResponse *)response {
    NSLog(@"MIME type of file: %@", [response MIMEType]);
    
    if ([[response MIMEType] isEqualToString:@"application/zip"]) {
        NSString *title = [NSString stringWithFormat:@"Download report: %@", [response.URL absoluteString]];
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:@"Canel" destructiveButtonTitle:nil otherButtonTitles:@"Download", nil];
        [actionSheet showInView:self.view];
    }

}


-(void)connection:(NSURLConnection *)connection didReceiveData:(nonnull NSData *)data {
    
}


-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    
}

@end
