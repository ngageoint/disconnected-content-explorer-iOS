//
//  WhirlyCloudViewController.m
//  DICE
//
//  Created by Robert St. John on 7/6/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "WhirlyCloudViewController.h"

#import "WhirlyGlobeComponent.h"
#import "LAZShader.h"
#import "LAZQuadReader.h"
#import "ResourceTypes.h"


@interface WhirlyCloudViewController () <WhirlyGlobeViewControllerDelegate, ResourceHandler>

@property Report *report;
@property NSURL *resource;

@end


@implementation WhirlyCloudViewController
{
    WhirlyGlobeViewController *globeViewC;
    MaplyShader *pointShaderRamp,*pointShaderColor;
}

- (void)handleResource:(NSURL *)resource forReport:(Report *)report
{
    self.report = report;
    self.resource = resource;
    if (!self.resource) {
        self.resource = self.report.url;
    }
    [self addLaz:self.resource.path rampShader:pointShaderRamp regularShader:pointShaderColor desc:@{}];
}

// Generate a standard color ramp
- (UIImage *)generateColorRamp
{
    MaplyColorRampGenerator *rampGen = [[MaplyColorRampGenerator alloc] init];
    [rampGen addHexColor:0x5e03e1];
    [rampGen addHexColor:0x2900fb];
    [rampGen addHexColor:0x0053f8];
    [rampGen addHexColor:0x02fdef];
    [rampGen addHexColor:0x00fe4f];
    [rampGen addHexColor:0x33ff00];
    [rampGen addHexColor:0xefff01];
    [rampGen addHexColor:0xfdb600];
    [rampGen addHexColor:0xff6301];
    [rampGen addHexColor:0xf01a0a];

    return [rampGen makeImage:CGSizeMake(256.0,1.0)];
}

// Maximum number of points we'd like to display
static int MaxDisplayedPoints = 3000000;

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Overrides for various databases
//    NSDictionary *dbDesc = @{
//        @"ot_35121F2416_1-B-quad-data": @{
//            kLAZReaderCoordSys:@"+proj=utm +zone=10 +datum=NAD83 +no_defs",
//            kLAZShaderPointSize: @(4.0),
//            kLAZReaderZOffset: @(2.0)
//        },
//        @"st-helens-quad-data": @{kLAZReaderColorScale: @(255.0)},
//        @"stadium-utm-quad-data": @{kLAZReaderColorScale: @(255.0)}
//    };

    // Set up the globe
    globeViewC = [[WhirlyGlobeViewController alloc] init];
    [self.view addSubview:globeViewC.view];
    globeViewC.view.frame = self.view.bounds;
    [self addChildViewController:globeViewC];
    globeViewC.frameInterval = 2;
    // globeViewC.performanceOutput = true;
    globeViewC.delegate = self;
    globeViewC.tiltGesture = true;
    globeViewC.autoMoveToTap = false;
    globeViewC.twoFingerTapGesture = false;

    // Give us a tilt
    [globeViewC setTiltMinHeight:0.001 maxHeight:0.01 minTilt:1.21771169 maxTilt:0.0];

    // Add a base layer
    NSString * baseCacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString * cacheDir = [NSString stringWithFormat:@"%@/maqquesttiles/", baseCacheDir];
    int maxZoom = 18;
    MaplyRemoteTileSource *tileSource = [[MaplyRemoteTileSource alloc] initWithBaseURL:@"http://mapbox.geointservices.io/v4/mapbox.osm-bright/" ext:@"png" minZoom:0 maxZoom:maxZoom];
    tileSource.cacheDir = cacheDir;
    MaplyQuadImageTilesLayer *layer = [[MaplyQuadImageTilesLayer alloc] initWithCoordSystem:tileSource.coordSys tileSource:tileSource];
    layer.handleEdges = true;
    layer.coverPoles = true;
    layer.drawPriority = 0;
    layer.color = [UIColor colorWithWhite:0.5 alpha:1.0];
    [globeViewC addLayer:layer];

    // Shader Shaders for color and ramp versions
    pointShaderColor = BuildPointShader(globeViewC);
    pointShaderRamp = BuildRampPointShader(globeViewC,[self generateColorRamp]);
}

- (void)addLaz:(NSString *)dbPath rampShader:(MaplyShader *)rampShader regularShader:(MaplyShader *)regShader desc:(NSDictionary *)desc
{
    if (!dbPath) {
        return;
    }

    // Set up the paging logic
    //        quadDelegate = [[LAZQuadReader alloc] initWithDB:lazPath indexFile:indexPath];
    MaplyCoordinate3dD ll,ur;
    LAZQuadReader *quadDelegate = [[LAZQuadReader alloc] initWithDB:dbPath desc:desc viewC:globeViewC];
    if (quadDelegate.hasColor) {
        quadDelegate.shader = regShader;
    }
    else {
        quadDelegate.shader = rampShader;
    }
    [quadDelegate getBoundsLL:&ll ur:&ur];

    // Start location
    WhirlyGlobeViewControllerAnimationState *viewState = [[WhirlyGlobeViewControllerAnimationState alloc] init];
    viewState.heading = -3.118891;
    viewState.height = 0.003194;
    viewState.tilt = 0.988057;
    MaplyCoordinate center = [[quadDelegate coordSys] localToGeo:[quadDelegate getCenter]];
    viewState.pos = MaplyCoordinateDMake(center.x,center.y);
    [globeViewC setViewState:viewState];

    MaplyQuadPagingLayer *lazLayer = [[MaplyQuadPagingLayer alloc] initWithCoordSystem:quadDelegate.coordSys delegate:quadDelegate];
    // It takes no real time to fetch from the database.
    // All the threading is in projecting coordinates
    lazLayer.numSimultaneousFetches = 4;
    lazLayer.maxTiles = [quadDelegate getNumTilesFromMaxPoints:MaxDisplayedPoints];
    lazLayer.importance = 128*128;
    lazLayer.minTileHeight = ll.z;
    lazLayer.maxTileHeight = ur.z;
    lazLayer.useParentTileBounds = false;
    [globeViewC addLayer:lazLayer];

    // Drop a label so the user can find it when zoomed out
    MaplyScreenLabel *label = [[MaplyScreenLabel alloc] init];
    label.text = [[dbPath lastPathComponent] stringByDeletingPathExtension];
    label.loc = center;
    [globeViewC addScreenLabels:@[label]
        desc:@{
            kMaplyMaxVis:@(10.0),
            kMaplyMinVis:@(0.1),
            kMaplyFont:[UIFont boldSystemFontOfSize:24.0]
        }];
}

@end
