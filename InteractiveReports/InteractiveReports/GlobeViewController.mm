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
#import "TrailsRenderer.hpp"

#import "KML.h"
#import "KMLPoint.h"
#import "KMLLineString.h"

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
    self.view.translatesAutoresizingMaskIntoConstraints = NO;
    self.preferredContentSize = CGSizeMake(480.0, 320.0);
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    nameLabel = [[UILabel alloc] init];
    
    htmlView = [[UIWebView alloc] init];
    htmlView.scalesPageToFit = NO;
    htmlView.contentScaleFactor = 2.0;
    
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    htmlView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.view addSubview:nameLabel];
    [self.view addSubview:htmlView];
    
    NSDictionary *views = @{
        @"root": self.view,
        @"html": htmlView,
        @"html_scroll": htmlView.scrollView,
        @"name": nameLabel
    };
    
    NSArray *constraints = @[
        @"H:[root(<=480.0)]",
        @"V:[root(<=320.0)]",
        @"H:|-[name]-|",
        @"H:|-[html]-|",
        @"V:|-[name]-[html]-|"
    ];
    
    for (NSString *vfl in constraints) {
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:vfl options:0 metrics:nil views:views]];
    }
}

- (void)setContentFromPlacemark:(KMLPlacemark *)placemark
{
    NSString *name = placemark.name;
    if (!name) {
        name = [NSString stringWithFormat:@"%@ Placemark", [placemark.geometry class]];
    }
    nameLabel.text = name;
    
    NSMutableString *desc = placemark.descriptionValue.mutableCopy;
    NSString *openCDATA = @"<![CDATA[";
    NSString *closeCDATA = @"]]>";
    if ([desc hasPrefix:openCDATA]) {
        [desc deleteCharactersInRange:NSMakeRange(0, openCDATA.length)];
        [desc deleteCharactersInRange:NSMakeRange(desc.length - closeCDATA.length, closeCDATA.length)];
    };
    [htmlView loadHTMLString:desc baseURL:nil];
    [htmlView.scrollView sizeToFit];
    
    NSLog(@"KML description content size: %fx%f", htmlView.scrollView.contentSize.width, htmlView.scrollView.contentSize.height);
    NSLog(@"KML description scroll size: %fx%f", htmlView.scrollView.bounds.size.width, htmlView.scrollView.bounds.size.height);
    
    [self.view setNeedsUpdateConstraints];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [htmlView loadHTMLString:@"" baseURL:nil];
}

@end


// TODO: figure out how to initialize g3m widget outside storyboard like G3MWidget_iOS#initWithCoder does
@implementation GlobeViewController

Geodetic3D *cameraPosition;
KMLPlacemarkViewController *kmlDescriptionView;
UIPopoverController *kmlDescriptionPopover;
NSMutableDictionary *kmlIconCache;


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
        std::list<Renderer *> renderers;
        [self createRenderersForKMLResource:resource rendererList:renderers];
        std::list<Renderer *>::iterator r = renderers.begin();
        while (r != renderers.end()) {
            builder.addRenderer(*r);
            r++;
        }
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
        cameraPosition = NULL;
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

- (void)createRenderersForKMLResource:(NSURL *)resource rendererList:(std::list<Renderer *>&)rendererList
{
    kmlDescriptionView = [[KMLPlacemarkViewController alloc] init];
    kmlDescriptionPopover = [[UIPopoverController alloc] initWithContentViewController:kmlDescriptionView];
    
    MarksRenderer *marks = new MarksRenderer(true);
    marks->setEnable(false);
    marks->setMarkTouchListener(new DICEMarkTouchListener(self), true);
    
    TrailsRenderer *trails = new TrailsRenderer();
    
    rendererList.push_back(marks);
    rendererList.push_back(trails);
    
    dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(backgroundQueue, ^{
        [self buildRenderingModelFromKML:resource pointRenderer:marks lineStringRenderer:trails];
    });
}

- (void)buildRenderingModelFromKML:(NSURL *)resource
    pointRenderer:(MarksRenderer *)pointRenderer
    lineStringRenderer:(TrailsRenderer *)lineStringRenderer
{
    KMLRoot *kml = [KMLParser parseKMLAtURL:resource];
    kmlIconCache = [[NSMutableDictionary alloc] init];
    CGFloat lat = 0.0, lon = 0.0, height = 5000.0;
    
    std::vector<Mark *> marks;
    
    NSArray *placemarks = [kml placemarks];
    for (KMLPlacemark *placemark in placemarks) {
        @autoreleasepool {
            if ([placemark.geometry isKindOfClass:KMLPoint.class]) {
                KMLPoint *point = (KMLPoint *)placemark.geometry;
                lat = point.coordinate.latitude;
                lon = point.coordinate.longitude;
                pointRenderer->addMark([self buildMarkFromKMLPoint:point]);
            }
            else if ([placemark.geometry isKindOfClass:[KMLLineString class]]) {
                KMLLineString *lineString = (KMLLineString *)placemark.geometry;
                if (lineString.coordinates.firstObject) {
                    KMLCoordinate *coord = (KMLCoordinate *)lineString.coordinates.firstObject;
                    lat = coord.latitude;
                    lon = coord.longitude;
                    [self buildTrailFromKMLLineString:lineString forRenderer:lineStringRenderer];
                }
            }
            
            if (!cameraPosition && lat != 0.0 && lon != 0.0) {
                if (height > 5000.0) {
                    height += 1000.0;
                }
                cameraPosition = new Geodetic3D(Angle::fromDegrees(lat), Angle::fromDegrees(lon), 5000.0);
            }
        }
    }
    
    [kmlIconCache removeAllObjects];
    kmlIconCache = nil;
    marks.clear();
    
    dispatch_async(dispatch_get_main_queue(), ^{
        pointRenderer->setEnable(true);
        [self didAddResourceRenderer];
    });
}

+ (void)parseKMLColorHexABGR:(NSString *)colorStr redOut:(CGFloat&)red greenOut:(CGFloat&)green blueOut:(CGFloat&)blue alphaOut:(CGFloat&)alpha
{
    NSScanner *colorScanner = [NSScanner scannerWithString:colorStr];
    unsigned long long colorValue = 0LL;
    [colorScanner scanHexLongLong:&colorValue];
    red = (colorValue & 0xFFLL) / 255.0f;
    green = ((colorValue & 0xFF00LL) >> 8) / 255.0f;
    blue = ((colorValue & 0xFF0000LL) >> 16) / 255.0f;
    alpha = ((colorValue & 0xFF000000LL) >> 24) / 255.0f;
}

+ (UIColor *)makeUIColorFromKMLColorHexABGR:(NSString *)colorStr
{
    CGFloat red, green, blue, alpha;
    [GlobeViewController parseKMLColorHexABGR:colorStr redOut:red greenOut:green blueOut:blue alphaOut:alpha];
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

- (Mark *)buildMarkFromKMLPoint:(KMLPoint *)point
{
    KMLPlacemark *placemark = (KMLPlacemark *)point.parent;
    KMLStyle *style = [placemark style];
    
    NSString *iconName = style.iconStyle.icon.href;
    if (!iconName) {
        iconName = @"fa-map-marker";
    }

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
    UIImage *icon = kmlIconCache[iconID];
    
    if (!icon) {
        NSLog(@"icon cache miss: %@", iconID);
        UIColor *iconColor = [GlobeViewController makeUIColorFromKMLColorHexABGR:iconColorHex];
        icon = [GlobeViewController createIconImage:iconName colored:iconColor atScale:iconScale];
        kmlIconCache[iconID] = icon;
    }
    
    IImage *markImage = new Image_iOS(icon, NULL);
    Mark *g3mMark = new Mark(markImage, iconID.UTF8String,
                             Geodetic3D::fromDegrees(point.coordinate.latitude, point.coordinate.longitude, point.coordinate.altitude),
                             RELATIVE_TO_GROUND);
    g3mMark->setUserData(new KMLMarkUserData(placemark));
    return g3mMark;
}

+ (UIImage *)createIconImage:(NSString *)iconName colored:(UIColor *)iconColor atScale:(CGFloat)iconScale
{
    if ([iconName hasPrefix:@"fa-"]) {
        return [UIImage imageWithIcon:iconName backgroundColor:[UIColor clearColor] iconColor:iconColor andSize:CGSizeMake(32.0f * iconScale, 32.0f * iconScale)];
    }
    UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfFile:iconName]];
//    image = [GlobeViewController tintImage:image color:iconColor];
    return image;
}

// TODO: figure this out - http://stackoverflow.com/questions/3514066/how-to-tint-a-transparent-png-image-in-iphone
+ (UIImage *)tintImage:(UIImage *)image color:(UIColor *)color
{
    CGSize size = image.size;
    CGFloat scale = [[UIScreen mainScreen] scale];
    UIGraphicsBeginImageContextWithOptions (size, NO, scale); // for correct resolution on retina, thanks @MobileVet
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    CGContextTranslateCTM(context, 0, image.size.height);
    CGContextScaleCTM(context, 1.0, -1.0);
    
    CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
    
    // image drawing code here
    // draw black background to preserve color of transparent pixels
    CGContextSetBlendMode(context, kCGBlendModeNormal);
    [[UIColor blackColor] setFill];
    CGContextFillRect(context, rect);
    
    // draw original image
    CGContextSetBlendMode(context, kCGBlendModeNormal);
    CGContextDrawImage(context, rect, image.CGImage);
    
    // tint image (loosing alpha) - the luminosity of the original image is preserved
    CGContextSetBlendMode(context, kCGBlendModeColor);
    [color setFill];
    CGContextFillRect(context, rect);
    
    // mask by alpha values of original image
    CGContextSetBlendMode(context, kCGBlendModeDestinationIn);
    CGContextDrawImage(context, rect, image.CGImage);
    
    UIImage *coloredImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return coloredImage;
}

- (void)buildTrailFromKMLLineString:(KMLLineString *)lineString forRenderer:(TrailsRenderer *)renderer
{
    CGFloat ribbonWidth = 200.0;
    CGFloat red = 1.0, green = 1.0, blue = 0.0, alpha = 1.0;
    CGFloat heightDelta = 0.0;
    
    KMLPlacemark *placemark = (KMLPlacemark *)lineString.parent;
    KMLStyle *style = [placemark style];
    if (style.lineStyle) {
        KMLLineStyle *lineStyle = style.lineStyle;
        if (lineStyle.color) {
            [GlobeViewController parseKMLColorHexABGR:lineStyle.color redOut:red greenOut:green blueOut:blue alphaOut:alpha];
        }
//        if (lineStyle.width > 0.0) {
//            ribbonWidth = lineStyle.width;
//        }
    }
    
    Trail *trail = new Trail(Color::fromRGBA(red, green, blue, alpha), ribbonWidth, heightDelta);
    for (KMLCoordinate *coord in lineString.coordinates) {
        trail->addPosition(Angle::fromDegrees(coord.latitude), Angle::fromDegrees(coord.longitude), coord.altitude);
    }
    renderer->addTrail(trail);
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
