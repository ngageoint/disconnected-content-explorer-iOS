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

@property (readonly, weak, nonatomic, getter=getGlobeView) G3MWidget_iOS *globeView;

- (G3MWidget_iOS *)getGlobeView;

@end

// TODO: figure out how to initialize g3m widget outside storyboard like G3MWidget_iOS#initWithCoder does
@implementation GlobeViewController

- (G3MWidget_iOS *)getGlobeView {
    return (G3MWidget_iOS *)self.view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    G3MBuilder_iOS builder(self.globeView);
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
//    self.globeView = nil;
}

- (void)handleResource:(NSURL *)resource {
    NSLog(@"GlobeViewController: loading resource %@", resource);
}

@end
