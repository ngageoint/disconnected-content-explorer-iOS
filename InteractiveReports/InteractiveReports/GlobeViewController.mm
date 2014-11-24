//
//  GlobeViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/7/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "GlobeViewController.h"
#import "G3MWidget_iOS.h"
#import "G3MBuilder_iOS.hpp"
#import "MeshRenderer.hpp"


@interface GlobeViewController ()

@property (strong, nonatomic) G3MWidget_iOS *globeView;

@end

@implementation GlobeViewController

- (void)loadView {
    self.view = self.globeView = [[G3MWidget_iOS alloc] init];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    G3MBuilder_iOS builder = G3MBuilder_iOS(self.globeView);
    builder.initializeWidget();
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// Start animation when view has appeared
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Start the glob3 render loop
    [self.globeView startAnimation];
}

// Stop the animation when view has disappeared
- (void)viewDidDisappear:(BOOL)animated {
    // Stop the glob3 render loop
    [self.globeView stopAnimation];
    [super viewDidDisappear:animated];
}

// Release property
- (void)viewDidUnload {
    self.globeView = nil;
}

- (void)handleResource:(NSURL *)resource {
    NSLog(@"GlobeViewController: loading resource %@", resource);
}

@end
