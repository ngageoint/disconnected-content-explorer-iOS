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

#import "KMLBalloonManualLayoutViewController.h"


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


// TODO: figure out how to initialize g3m widget outside storyboard like G3MWidget_iOS#initWithCoder does
@implementation GlobeViewController

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

Geodetic3D *cameraPosition;
UIPopoverController *kmlDescriptionPopover;
NSMutableDictionary *kmlIconCache;
NSDictionary *faNameForGoogleEarthIcon;
NSFileManager *fileManager;
NSURL *docsDir;
BOOL isDisappearing = NO;


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    isDisappearing = NO;
    fileManager = [NSFileManager defaultManager];
    docsDir = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    
    NSURL *googleEarthToFontawesomeFile = [docsDir URLByAppendingPathComponent:@"google_earth_to_fontawesome.json"];
    if ( [fileManager fileExistsAtPath:googleEarthToFontawesomeFile.path]) {
        NSError *jsonError;
        faNameForGoogleEarthIcon = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:googleEarthToFontawesomeFile] options:kNilOptions error:&jsonError];
    }
    
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
 
    isDisappearing = YES;
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
    MarksRenderer *marks = new MarksRenderer(true);
    marks->setEnable(false);
    marks->setMarkTouchListener(new DICEMarkTouchListener(self), true);
    
    TrailsRenderer *trails = new TrailsRenderer();
    
    rendererList.push_back(marks);
    rendererList.push_back(trails);
    
    dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
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
        if (isDisappearing) {
            break;
        }
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

- (Mark *)buildMarkFromKMLPoint:(KMLPoint *)point
{
    KMLPlacemark *placemark = (KMLPlacemark *)point.parent;
    KMLStyle *style = [placemark style];
    
    CGFloat iconScale = style.iconStyle.scale;
    if (iconScale == 0.0f) {
        iconScale = 1.0f;
    }
    
    NSString *iconColorHex = style.iconStyle.color.lowercaseString;
    if (!iconColorHex) {
        iconColorHex = @"ff00ffff"; // yellow
    }
    UIColor *iconColor = [GlobeViewController makeUIColorFromKMLColorHexABGR:iconColorHex];
    
    NSString *iconHref = style.iconStyle.icon.href;
    NSString *iconName;
    
    if (iconHref) {
        iconHref = iconHref.lastPathComponent;
        iconName = faNameForGoogleEarthIcon[iconHref];
    }
    
    if (!iconName && iconHref) {
        NSURL *iconPath = [docsDir URLByAppendingPathComponent:iconHref];
        if ([fileManager fileExistsAtPath:iconPath.path]) {
            iconName = iconPath.path;
        }
    }
    
    if (!iconName) {
        iconName = @"fa-map-marker";
    }
    
    NSString *iconID = [NSString stringWithFormat:@"%@:%@", iconName, iconColorHex];
    UIImage *icon = kmlIconCache[iconID];
    
    if (!icon) {
        NSLog(@"icon cache miss: %@", iconID);
        if ([iconName hasPrefix:@"fa-"]) {
            icon = [UIImage imageWithIcon:iconName backgroundColor:[UIColor clearColor] iconColor:iconColor andSize:CGSizeMake(32.0f * iconScale, 32.0f * iconScale)];
        }
        else {
            icon = [UIImage imageWithData:[NSData dataWithContentsOfFile:iconName]];
//            icon = [GlobeViewController tintImage:image color:iconColor];
        }
        kmlIconCache[iconID] = icon;
    }
    
    IImage *markImage = new Image_iOS(icon, NULL);
    Mark *g3mMark = new Mark(markImage, iconID.UTF8String,
                             Geodetic3D::fromDegrees(point.coordinate.latitude, point.coordinate.longitude, point.coordinate.altitude),
                             RELATIVE_TO_GROUND);
    g3mMark->setUserData(new KMLMarkUserData(placemark));
    return g3mMark;
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
    // TODO: hard coded for now so line is actually visible
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
    CGRect markRect = CGRectMake(markPixel._x - markWidth / 2, markPixel._y - markHeight / 2, markWidth, markHeight);
    KMLMarkUserData *markData = (KMLMarkUserData *)mark->getUserData();
    KMLPlacemark *kml = markData->_kmlPlacemark;
    if (!kml) {
        return;
    }
    KMLBalloonManualLayoutViewController *balloon = [[KMLBalloonManualLayoutViewController alloc] initWithPlacemark:kml];
    kmlDescriptionPopover = [[UIPopoverController alloc] initWithContentViewController:balloon];
    kmlDescriptionPopover.backgroundColor = [UIColor whiteColor];
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
