//
//  GeoPackageTableMapData.m
//  DICE
//
//  Created by Brian Osborn on 2/29/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "GeoPackageTableMapData.h"

@interface GeoPackageTableMapData()
    @property (nonatomic, strong) NSString * name;
@end

@implementation GeoPackageTableMapData

-(id) initWithName: (NSString *) name{
    if (self = [super init]) {
        self.name = name;
    }
    
    return self;
}

-(NSString *) getName{
    return self.name;
}

-(void) addFeatureOverlayQuery: (GPKGFeatureOverlayQuery *) query{
    if( self.featureOverlayQueries == nil){
        self.featureOverlayQueries = [[NSMutableArray alloc] init];
    }
    [self.featureOverlayQueries addObject:query];
}

-(void) addMapShape: (GPKGMapShape *) shape{
    if( self.mapShapes == nil){
        self.mapShapes = [[NSMutableArray alloc] init];
    }
    [self.mapShapes addObject:shape];
}

-(void) removeFromMapView: (MKMapView *) mapView{
    
    if(self.boundedOverlay != nil){
        dispatch_sync(dispatch_get_main_queue(), ^{
            [mapView removeOverlay:self.boundedOverlay];
        });
    }
    
    if( self.mapShapes != nil){
        for(GPKGMapShape * mapShape in self.mapShapes){
            dispatch_sync(dispatch_get_main_queue(), ^{
                [mapShape removeFromMapView:mapView];
            });
        }
    }
}

@end
