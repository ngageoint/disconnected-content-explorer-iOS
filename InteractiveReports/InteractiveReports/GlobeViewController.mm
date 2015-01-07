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
#import "MarkTouchListener.hpp"
#import "Mesh.hpp"
#import "MeshRenderer.hpp"
#import "Planet.hpp"
#import "PlanetRendererBuilder.hpp"
#import "SingleBilElevationDataProvider.hpp"


#import "KML.h"
#import "KMLPoint.h"

#import "NSString+FontAwesome.h"
#import "UIImage+FontAwesome.h"


@interface GlobeViewController ()

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingIndicator;
@property (weak, nonatomic) IBOutlet G3MWidget_iOS *globeView;

- (void)onBeforeAddMesh:(Mesh *)mesh;
- (void)onAfterAddMesh:(Mesh *)mesh;
- (void)onKMLMarkTouched:(Mark *)mark;

@end


class DICEMarkTouchListener : public MarkTouchListener {
public:
    DICEMarkTouchListener(GlobeViewController *controller) : _controller(controller) {};
    ~DICEMarkTouchListener() {
        _controller = nil;
    }
    bool touchedMark(Mark *mark) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_controller onKMLMarkTouched:mark];
        });
        return true;
    }
    
private:
    GlobeViewController *_controller;
};

class KMLMarkUserData : public MarkUserData {
public:
    KMLMarkUserData(KMLPlacemark *kmlPlacemark) : _kmlPlacemark(kmlPlacemark) {};
    ~KMLMarkUserData() {
        _kmlPlacemark = nil;
    }
    KMLPlacemark *_kmlPlacemark;
};

class DICEMeshLoadListener : public MeshLoadListener {
    
public:
    DICEMeshLoadListener(GlobeViewController *controller) : _controller(controller) {};
    ~DICEMeshLoadListener() {
        _controller = nil;
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


@interface KMLPlacemarkViewController : UIViewController

- (void)setContentFromPlacemark:(KMLPlacemark *)placemark;

@end

@implementation KMLPlacemarkViewController

UILabel *nameLabel;
UIWebView *htmlView;

- (void)viewDidLoad
{
    self.preferredContentSize = CGSizeMake(480.0, 320.0);
    htmlView = [[UIWebView alloc] init];
    htmlView.scalesPageToFit = YES;
    [self.view addSubview:htmlView];
}

- (void)viewWillAppear:(BOOL)animated
{
    htmlView.frame = self.view.bounds;
}

- (void)setContentFromPlacemark:(KMLPlacemark *)placemark
{
    NSMutableString *desc = placemark.descriptionValue.mutableCopy;
    NSString *openCDATA = @"<![CDATA[";
    NSString *closeCDATA = @"]]>";
    if ([desc hasPrefix:openCDATA]) {
        [desc deleteCharactersInRange:NSMakeRange(0, openCDATA.length)];
        [desc deleteCharactersInRange:NSMakeRange(desc.length - closeCDATA.length, closeCDATA.length)];
    };
    [htmlView loadHTMLString:desc baseURL:nil];
}

@end


// TODO: figure out how to initialize g3m widget outside storyboard like G3MWidget_iOS#initWithCoder does
@implementation GlobeViewController

Geodetic3D *cameraPosition;
KMLPlacemarkViewController *kmlDescriptionView;
UIPopoverController *kmlDescriptionPopover;


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
}

- (void)handleResource:(NSURL *)resource forReport:(Report *)report
{
    G3MBuilder_iOS builder(self.globeView);
    builder.getPlanetRendererBuilder()->setVerticalExaggeration(1.0f);
    NSURL *elevationDataUrl = [[NSBundle mainBundle] URLForResource:@"full-earth-2048x1024" withExtension:@"bil"];
    ElevationDataProvider* elevationDataProvider = new SingleBilElevationDataProvider(
        URL(elevationDataUrl.absoluteString.UTF8String, false), Sector::fullSphere(), Vector2I(2048, 1024));
    // so meters above sea-level z-coordinates render at the correct height:
    builder.getPlanetRendererBuilder()->setElevationDataProvider(elevationDataProvider);
    
    if ([resource.pathExtension isEqualToString:@"kml"]) {
        builder.addRenderer([self createRendererForKMLResource:resource]);
    }
    else {
        builder.addRenderer([self createMeshRendererForPointcloudResource:resource]);
    }
    
    builder.initializeWidget();
}

- (void)didAddResourceRenderer
{
    [self.loadingIndicator stopAnimating];
    if (cameraPosition) {
        [self.globeView setAnimatedCameraPosition:*cameraPosition];
        delete cameraPosition;
    }
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
    [self performSelectorOnMainThread:@selector(didAddResourceRenderer) withObject:nil waitUntilDone:NO];
}

- (Renderer *)createRendererForKMLResource:(NSURL *)resource
{
    kmlDescriptionView = [[KMLPlacemarkViewController alloc] init];
    kmlDescriptionPopover = [[UIPopoverController alloc] initWithContentViewController:kmlDescriptionView];
    
    MarksRenderer *renderer = new MarksRenderer(true);
    renderer->setMarkTouchListener(new DICEMarkTouchListener(self), true);
    
    dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(backgroundQueue, ^{
        [self buildMarkersFromKML:resource forRenderer:renderer];
    });
    
    return renderer;
}

- (void)buildMarkersFromKML:(NSURL *)resource forRenderer:(MarksRenderer *)renderer
{
    KMLRoot *root = [KMLParser parseKMLAtURL:resource];
    NSMutableDictionary *iconCache = [[NSMutableDictionary alloc] init];
    
    for (KMLPlacemark *placemark in [root placemarks]) {
        if ([placemark.geometry isKindOfClass:KMLPoint.class]) {
            KMLPoint *point = (KMLPoint *)placemark.geometry;
            
            if (!cameraPosition) {
                cameraPosition = new Geodetic3D(
                    Angle::fromDegrees(point.coordinate.latitude),
                    Angle::fromDegrees(point.coordinate.longitude),
                    5000.0);
            }
            
            KMLStyle *style = [placemark style];
            
            NSString *iconName = style.iconStyle.icon.href;
            if ([iconName hasSuffix:@"road_shield3.png"]) {
                iconName = @"fa-circle";
            }
            else {
                iconName = @"fa-map-marker";
            }
            
            CGFloat iconScale = style.iconStyle.scale;
            if (iconScale == 0.0f) {
                iconScale = 1.0f;
            }
            
            NSString *iconColorHex = style.iconStyle.color.lowercaseString;
            if (!iconColorHex) {
                iconColorHex = @"ff00ffff"; // yellow
            }
            
            NSString *iconID = [NSString stringWithFormat:@"%@:%@", iconName, iconColorHex];
            UIImage *icon = iconCache[iconID];
            
            if (!icon) {
                NSLog(@"icon cache miss: %@", iconID);
                NSScanner *colorScanner = [NSScanner scannerWithString:iconColorHex];
                unsigned long long colorValue = 0LL;
                [colorScanner scanHexLongLong:&colorValue];
                CGFloat red = (colorValue & 0xFFLL) / 255.0f;
                CGFloat green = ((colorValue & 0xFF00LL) >> 8) / 255.0f;
                CGFloat blue = ((colorValue & 0xFF0000LL) >> 16) / 255.0f;
                CGFloat alpha = ((colorValue & 0xFF000000LL) >> 24) / 255.0f;
                UIColor *iconColor = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
                icon = [UIImage imageWithIcon:iconName backgroundColor:[UIColor clearColor] iconColor:iconColor andSize:CGSizeMake(32.0f * iconScale, 32.0f * iconScale)];
                iconCache[iconID] = icon;
            }
            
            IImage *markImage = new Image_iOS(icon, NULL);
            Mark *g3mMark = new Mark(markImage, iconID.UTF8String,
                                     Geodetic3D::fromDegrees(point.coordinate.latitude, point.coordinate.longitude, point.coordinate.altitude),
                                     RELATIVE_TO_GROUND);
            g3mMark->setUserData(new KMLMarkUserData(placemark));
            renderer->addMark(g3mMark);
        }
    }
    
    [iconCache removeAllObjects];
    
    [self performSelectorOnMainThread:@selector(didAddResourceRenderer) withObject:nil waitUntilDone:NO];
}

- (void)buildLineStringsFromKML:(KMLRoot *)resource forRenderer:(TrailsRenderer *)renderer
{
    
}

- (void)onKMLMarkTouched:(Mark *)mark
{
    Vector3D *markPos = mark->getCartesianPosition(self.globeView.widget->getG3MContext()->getPlanet());
    Vector2F markPixel = self.globeView.widget->getCurrentCamera()->point2Pixel(*markPos);
    CGFloat markHeight = mark->getTextureHeight();
    CGFloat markWidth = mark->getTextureWidth();
    CGRect markRect = CGRectMake(markPixel._x - markWidth / 1.3, markPixel._y - markHeight / 2, markWidth, markHeight);
    KMLMarkUserData *markData = (KMLMarkUserData *)mark->getUserData();
    KMLPlacemark *kml = markData->_kmlPlacemark;
    if (!kml) {
        return;
    }
    [kmlDescriptionView setContentFromPlacemark:kml];
    [kmlDescriptionPopover presentPopoverFromRect:markRect inView:self.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:NO];
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
