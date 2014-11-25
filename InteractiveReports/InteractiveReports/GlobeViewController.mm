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

@property (weak, nonatomic) IBOutlet G3MWidget_iOS *globeView;

@property (nonatomic) MeshRenderer *meshRenderer;

@end

// TODO: figure out how to initialize g3m widget outside storyboard like G3MWidget_iOS#initWithCoder does
@implementation GlobeViewController

- (G3MWidget_iOS *)getGlobeView {
    return (G3MWidget_iOS *)self.view;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    G3MBuilder_iOS builder(self.globeView);
    self.meshRenderer = new MeshRenderer();
    builder.addRenderer(self.meshRenderer);
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
    self.meshRenderer->clearMeshes();
    [super viewDidDisappear:animated];
}

// Release property
- (void)viewDidUnload {
}

- (void)handleResource:(NSURL *)resource {
    float pointSize = 2.0;
    double deltaHeight = 0.0;
    MeshLoadListener *loadListener = NULL;
    bool deleteListener = true;
    NSString *resourceName = resource.absoluteString;
    self.meshRenderer->loadJSONPointCloud(
        URL([resourceName UTF8String]),
        pointSize, deltaHeight, loadListener, deleteListener);
}

@end
