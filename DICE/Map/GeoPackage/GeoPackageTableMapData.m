//
//  GeoPackageTableMapData.m
//  DICE
//
//  Created by Brian Osborn on 2/29/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "GeoPackageTableMapData.h"
#import "GPKGProjectionFactory.h"
#import "GPKGProjectionConstants.h"

@interface GeoPackageTableMapData()
@property (nonatomic, strong) NSString * name;
@property (nonatomic, strong) GPKGProjection * projection;
@end

@implementation GeoPackageTableMapData

-(id) initWithName: (NSString *) name{
    if (self = [super init]) {
        self.name = name;
        self.projection = [GPKGProjectionFactory getProjectionWithInt:PROJ_EPSG_WORLD_GEODETIC_SYSTEM];
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

-(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andMap: (MKMapView *) mapView{
    NSMutableString * message = nil;
    
    if(self.featureOverlayQueries != nil){
        for(GPKGFeatureOverlayQuery * featureOverlayQuery in self.featureOverlayQueries){
            NSString * overlayMessage = [featureOverlayQuery buildMapClickMessageWithLocationCoordinate:locationCoordinate andMapView:mapView andProjection:self.projection];
            if(overlayMessage != nil){
                if(message == nil){
                    message = [[NSMutableString alloc] init];
                }else{
                    [message appendString:@"\n\n"];
                }
                [message appendString:overlayMessage];
            }
        }
    }
    
    return message;
}

-(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds: (GPKGBoundingBox *) mapBounds{
    NSMutableString * message = nil;
    
    if(self.featureOverlayQueries != nil){
        for(GPKGFeatureOverlayQuery * featureOverlayQuery in self.featureOverlayQueries){
            NSString * overlayMessage = [featureOverlayQuery buildMapClickMessageWithLocationCoordinate:locationCoordinate andZoom:zoom andMapBounds:mapBounds andProjection:self.projection];
            if(overlayMessage != nil){
                if(message == nil){
                    message = [[NSMutableString alloc] init];
                }else{
                    [message appendString:@"\n\n"];
                }
                [message appendString:overlayMessage];
            }
        }
    }
    
    return message;
}

-(GPKGFeatureTableData *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andMap: (MKMapView *) mapView{
    GPKGFeatureTableData * tableData = nil;
    
    if(self.featureOverlayQueries != nil){
        for(GPKGFeatureOverlayQuery * featureOverlayQuery in self.featureOverlayQueries){
            tableData = [featureOverlayQuery buildMapClickTableDataWithLocationCoordinate:locationCoordinate andMapView:mapView andProjection:self.projection];
        }
    }
    
    return tableData;
}

-(GPKGFeatureTableData *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds: (GPKGBoundingBox *) mapBounds{
    GPKGFeatureTableData * tableData = nil;
    
    if(self.featureOverlayQueries != nil){
        for(GPKGFeatureOverlayQuery * featureOverlayQuery in self.featureOverlayQueries){
            tableData = [featureOverlayQuery buildMapClickTableDataWithLocationCoordinate:locationCoordinate andZoom:zoom andMapBounds:mapBounds andProjection:self.projection];
        }
    }
    
    return tableData;
}

@end
