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
#import "Image_iOS.hpp"
#import "Mark.hpp"
#import "MarksRenderer.hpp"
#import "Mesh.hpp"
#import "MeshRenderer.hpp"
#import "Planet.hpp"
#import "PlanetRendererBuilder.hpp"
#import "SingleBilElevationDataProvider.hpp"
#import "Vector3D.hpp"

#import "SimpleKML.h"
#import "SimpleKMLBalloonStyle.h"
#import "SimpleKMLColorStyle.h"
#import "SimpleKMLIconStyle.h"
#import "SimpleKMLOverlay.h"
#import "SimpleKMLDocument.h"
#import "SimpleKMLPlacemark.h"
#import "SimpleKMLPoint.h"
#import "SimpleKMLStyle.h"


@interface GlobeViewController ()

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingIndicator;
@property (weak, nonatomic) IBOutlet G3MWidget_iOS *globeView;

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
@implementation GlobeViewController {
    Geodetic3D *cameraPosition;
}

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
    
    self.globeView.userInteractionEnabled = NO;
    [self.loadingIndicator startAnimating];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"DICE globe view memory warning");
}

- (void)viewWillAppear:(BOOL)animated
{
    // Start the glob3 render loop
    [self.globeView startAnimation];
}

// Start animation when view has appeared
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

// Stop the animation when view has disappeared
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    // Stop the glob3 render loop
    [self.globeView stopAnimation];
//    delete meshRenderer;
}

- (void)handleResource:(NSURL *)resource forReport:(Report *)report
{
    Renderer *renderer;
    if ([resource.pathExtension isEqualToString:@"kml"]) {
        renderer = [self createRendererForKMLResource:resource];
    }
    else {
        renderer = [self createMeshRendererForPointcloudResource:resource];
    }
    
    G3MBuilder_iOS builder(self.globeView);
    
    builder.getPlanetRendererBuilder()->setVerticalExaggeration(1.0f);
    NSURL *elevationDataUrl = [[NSBundle mainBundle] URLForResource:@"full-earth-2048x1024" withExtension:@"bil"];
    ElevationDataProvider* elevationDataProvider = new SingleBilElevationDataProvider(
        URL(elevationDataUrl.absoluteString.UTF8String, false), Sector::fullSphere(), Vector2I(2048, 1024));
    // so meters above sea-level z-coordinates render at the correct height:
    builder.getPlanetRendererBuilder()->setElevationDataProvider(elevationDataProvider);
    builder.addRenderer(renderer);
    builder.initializeWidget();
}

- (void)didAddResourceRenderer
{
    [self.loadingIndicator stopAnimating];
    [self.globeView setAnimatedCameraPosition:*cameraPosition];
    self.globeView.userInteractionEnabled = YES;
}

- (void)onBeforeAddMesh:(Mesh *)mesh
{
}

- (void)onAfterAddMesh:(Mesh *)mesh
{
    Vector3D center = mesh->getCenter();
    const Planet *planet = [self.globeView widget]->getG3MContext()->getPlanet();
    Geodetic3D geoCenter = planet->toGeodetic3D(center);
    cameraPosition = new Geodetic3D(geoCenter._latitude, geoCenter._longitude, geoCenter._height + 5000.0);
    [self didAddResourceRenderer];
}

- (Renderer *)createRendererForKMLResource:(NSURL *)resource
{
    MarksRenderer *renderer = new MarksRenderer(true);
    SimpleKML *kml = [SimpleKML KMLWithContentsOfURL:resource error:NULL];
    SimpleKMLDocument *doc = (SimpleKMLDocument *)kml.feature;
    for (SimpleKMLPlacemark *kmlPlacemark in doc.flattenedPlacemarks) {
        UIImage *icon = kmlPlacemark.style.iconStyle.icon;
        if (!icon) {
            icon = [UIImage imageNamed:@"map-point"];
        }
        IImage *markImage = new Image_iOS(icon, NULL);
        Mark *g3mMark = new Mark(markImage, "map-point",
            Geodetic3D::fromDegrees(kmlPlacemark.point.coordinate.latitude, kmlPlacemark.point.coordinate.longitude, 0.0),
            RELATIVE_TO_GROUND);
        renderer->addMark(g3mMark);
        if (!cameraPosition) {
            cameraPosition = new Geodetic3D(
                Angle::fromDegrees(kmlPlacemark.point.coordinate.latitude),
                Angle::fromDegrees(kmlPlacemark.point.coordinate.longitude),
                5000.0);
        }
    }
    [self performSelectorOnMainThread:@selector(didAddResourceRenderer) withObject:nil waitUntilDone:NO];
    return renderer;
}
    
- (Renderer *)createMeshRendererForPointcloudResource:(NSURL *)resource
{
    MeshRenderer *meshRenderer = new MeshRenderer();
    float pointSize = 2.0;
    double deltaHeight = 0.0;
    MeshLoadListener *loadListener = new DICEMeshLoadListener(self);
    bool deleteListener = true;
    NSString *resourceName = resource.absoluteString;
    meshRenderer->loadJSONPointCloud(
        URL([resourceName UTF8String]),
        pointSize, deltaHeight, loadListener, deleteListener);
    return meshRenderer;
}

@end
