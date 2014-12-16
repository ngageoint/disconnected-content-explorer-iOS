//
//  GlobeViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/7/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "GlobeViewController.h"

#import "Context.hpp"
#import "ElevationDataProvider.hpp"
#import "G3MWidget_iOS.h"
#import "G3MWidget.hpp"
#import "G3MBuilder_iOS.hpp"
#import "Mesh.hpp"
#import "MeshRenderer.hpp"
#import "Planet.hpp"
#import "PlanetRendererBuilder.hpp"
#import "SingleBilElevationDataProvider.hpp"
#import "Vector3D.hpp"


@interface GlobeViewController ()

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingIndicator;
@property (weak, nonatomic) IBOutlet G3MWidget_iOS *globeView;
@property (nonatomic) MeshRenderer *meshRenderer;


- (void)onBeforeAddMesh:(Mesh*)mesh;
- (void)onAfterAddMesh:(Mesh*)mesh;

@end


class DICEMeshLoadListener : public MeshLoadListener {
    
public:
    DICEMeshLoadListener(GlobeViewController *controller) : _controller(controller) {};
    ~DICEMeshLoadListener() {
        _controller = NULL;
    }
    void onAfterAddMesh(Mesh *mesh) {
        [_controller onAfterAddMesh:mesh];
    }
    void onBeforeAddMesh(Mesh *mesh) {
        [_controller onBeforeAddMesh:mesh];
    }
    void onError(const URL& url) {}
    
private:
    GlobeViewController *_controller;
    
};


// TODO: figure out how to initialize g3m widget outside storyboard like G3MWidget_iOS#initWithCoder does
@implementation GlobeViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.loadingIndicator.autoresizingMask =
        UIViewAutoresizingFlexibleBottomMargin |
        UIViewAutoresizingFlexibleHeight |
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleWidth;
    
    G3MBuilder_iOS builder(self.globeView);
    
    builder.getPlanetRendererBuilder()->setVerticalExaggeration(1.0f);
    NSURL *elevationDataUrl = [[NSBundle mainBundle] URLForResource:@"full-earth-2048x1024" withExtension:@"bil"];
    ElevationDataProvider* elevationDataProvider = new SingleBilElevationDataProvider(
        URL(elevationDataUrl.absoluteString.UTF8String, false), Sector::fullSphere(), Vector2I(2048, 1024));
    // so meters above sea-level z-coordinates render at the correct height:
    builder.getPlanetRendererBuilder()->setElevationDataProvider(elevationDataProvider);
    self.meshRenderer = new MeshRenderer();
    builder.addRenderer(self.meshRenderer);
    builder.initializeWidget();
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"DICE globe view memory warning");
}

- (void)viewWillAppear:(BOOL)animated
{
    self.globeView.userInteractionEnabled = NO;
    [self.loadingIndicator startAnimating];
}

// Start animation when view has appeared
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Start the glob3 render loop
    [self.globeView startAnimation];
}

// Stop the animation when view has disappeared
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    // Stop the glob3 render loop
    [self.globeView stopAnimation];
    delete self.meshRenderer;
}

- (void)handleResource:(NSURL *)resource
{
    float pointSize = 2.0;
    double deltaHeight = 0.0;
    MeshLoadListener *loadListener = new DICEMeshLoadListener(self);
    bool deleteListener = true;
    NSString *resourceName = resource.absoluteString;
    self.meshRenderer->loadJSONPointCloud(
        URL([resourceName UTF8String]),
        pointSize, deltaHeight, loadListener, deleteListener);
}

- (void)onBeforeAddMesh:(Mesh *)mesh
{
}

- (void)onAfterAddMesh:(Mesh *)mesh
{
    Vector3D center = mesh->getCenter();
    const Planet *planet = [self.globeView widget]->getG3MContext()->getPlanet();
    Geodetic3D geoCenter = planet->toGeodetic3D(center);
    Geodetic3D lookingAtMesh = Geodetic3D(geoCenter._latitude, geoCenter._longitude, geoCenter._height + 5000.0);
    [self.globeView setAnimatedCameraPosition:lookingAtMesh];
    [self.loadingIndicator stopAnimating];
    self.globeView.userInteractionEnabled = YES;
}

@end
