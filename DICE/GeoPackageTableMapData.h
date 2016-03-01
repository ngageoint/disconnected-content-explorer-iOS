//
//  GeoPackageTableMapData.h
//  DICE
//
//  Created by Brian Osborn on 2/29/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GPKGFeatureOverlayQuery.h"
#import "GPKGMapShape.h"

@interface GeoPackageTableMapData : NSObject

@property (nonatomic, strong) GPKGBoundedOverlay * boundedOverlay;
@property (nonatomic, strong) NSMutableArray<GPKGFeatureOverlayQuery *> * featureOverlayQueries;
@property (nonatomic, strong) NSMutableArray<GPKGMapShape *> * mapShapes;

-(id) initWithName: (NSString *) name;

-(NSString *) getName;

-(void) addFeatureOverlayQuery: (GPKGFeatureOverlayQuery *) query;

-(void) addMapShape: (GPKGMapShape *) shape;

-(void) removeFromMapView: (MKMapView *) mapView;

@end
