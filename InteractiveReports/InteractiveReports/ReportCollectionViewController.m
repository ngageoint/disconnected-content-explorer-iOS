//
//  ReportCollectionViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/18/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "ReportCollectionView.h"
#import "ReportCollectionViewController.h"
#import "ReportViewController.h"
#import "PDFViewController.h"
#import "ReportAPI.h"


@interface ReportCollectionViewController () <ReportCollectionViewDelegate>

@property (weak, nonatomic) IBOutlet UIView *collectionSubview;

- (IBAction)viewChanged:(UISegmentedControl *)sender;

@end


@implementation ReportCollectionViewController

const NSArray *views;

NSInteger currentViewIndex;
NSArray *reports;
Report *selectedReport;

- (void)viewDidLoad {
    [super viewDidLoad];

    views = [[NSArray alloc] initWithObjects:
             [self.storyboard instantiateViewControllerWithIdentifier: @"listCollectionView"],
             [self.storyboard instantiateViewControllerWithIdentifier: @"tileCollectionView"],
             [self.storyboard instantiateViewControllerWithIdentifier: @"mapCollectionView"],
             nil];
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
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleURLRequest:) name:@"DICEURLOpened" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearSrcScheme:) name:@"DICEClearSrcScheme" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    [[ReportAPI sharedInstance] loadReports];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidAppear:(BOOL)animated {
    // Some special case stuff, if there is only one report, we may want to open it rather than present the list
    if (reports.count == 1) {
        // if we have a srcSchema, then another app called into DICE, open the report
        if ((_srcScheme != nil && ![_srcScheme isEqualToString:@""])) {
            [self performSegueWithIdentifier:@"showSingleReport" sender:self];
        }
        else if (self.didBecomeActive) {
            // TODO: handle in app delegate
            [self performSegueWithIdentifier:@"showSingleReport" sender:self];
        }
        self.didBecomeActive = NO;
    }
}

- (void)handleURLRequest:(NSNotification*)notification {
    _urlParams = notification.userInfo;
    _srcScheme = _urlParams[@"srcScheme"];
    _reportID = _urlParams[@"reportID"];
    
    NSLog(@"URL parameters: srcScheme: %@ reportID: %@", _srcScheme, _reportID);

    if (!_reportID) {
        return;
    }
    
    [reports enumerateObjectsUsingBlock: ^(Report* report, NSUInteger idx, BOOL *stop) {
        if ([report.reportID isEqualToString:_reportID]) {
            [self reportSelectedToView:report];
            *stop = YES;
        }
    }];
}

- (void)clearSrcScheme:(NSNotification*)notification {
    _srcScheme = @"";
    _didBecomeActive = NO;
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([[segue identifier] isEqualToString:@"showHtmlReport"]) {
        ReportViewController *reportViewController = (ReportViewController *)segue.destinationViewController;
        reportViewController.report = selectedReport;
        if (_srcScheme) {
            reportViewController.srcScheme = _srcScheme;
            reportViewController.urlParams = _urlParams;
        }
    }
    else if ([[segue identifier] isEqualToString:@"showPdfReport"]) {
        PDFViewController *pdfViewController = (PDFViewController *)segue.destinationViewController;
        pdfViewController.report = selectedReport;
    }
    else if ([[segue identifier] isEqualToString:@"showSingleReport"]) {
        ReportViewController *reportViewController = (ReportViewController *)segue.destinationViewController;
        reportViewController.srcScheme = _srcScheme;
        reportViewController.urlParams = _urlParams;
        reportViewController.report = [reports objectAtIndex:0];
        reportViewController.singleReport = YES;
        // TODO: make sure this behaves as expected
//        reportViewController.unzipComplete = _singleReportLoaded;
        reportViewController.unzipComplete = selectedReport.isEnabled;
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
    if ([selectedReport.fileExtension isEqualToString:@"html"]) {
        [self performSegueWithIdentifier:@"showHtmlReport" sender:self];
    }
    else if ([selectedReport.fileExtension isEqualToString:@"pdf"]) {
        [self performSegueWithIdentifier:@"showPdfReport" sender:self];
    }
    else {
        [self performSegueWithIdentifier:@"showHtmlReport" sender:self];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
