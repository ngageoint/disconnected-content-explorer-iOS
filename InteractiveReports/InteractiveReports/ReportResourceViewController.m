//
//  ReportLinkedResourceViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/21/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "ReportResourceViewController.h"

#import "NoteViewController.h"
#import "ResourceTypes.h"

@interface ReportResourceViewController ()

@property (weak, nonatomic) UIViewController<ResourceHandler> *resourceViewer;
@property (weak, nonatomic) IBOutlet UIView *resourceView;

@end

@implementation ReportResourceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIViewController<ResourceHandler> *resourceViewer = [ResourceTypes viewerForResource:self.resource];
    [self addChildViewController:resourceViewer];
    resourceViewer.view.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    resourceViewer.view.frame = self.resourceView.frame;
    [self.resourceView addSubview:resourceViewer.view];
    [resourceViewer didMoveToParentViewController:self];
    
    [resourceViewer handleResource:self.resource forReport:self.report];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    [self.resourceViewer willMoveToParentViewController:nil];
    [self.resourceViewer.view removeFromSuperview];
    [self.resourceViewer removeFromParentViewController];
    self.resourceViewer = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([[segue identifier] isEqualToString:@"showReportNotes"]) {
        NoteViewController *noteViewController = (NoteViewController *)segue.destinationViewController;
        noteViewController.report = self.report;
    }
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/


@end
