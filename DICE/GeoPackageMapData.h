//
//  GeoPackageMapData.h
//  DICE
//
//  Created by Brian Osborn on 2/29/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GeoPackageTableMapData.h"

@interface GeoPackageMapData : NSObject

-(id) initWithName: (NSString *) name;

-(NSString *) getName;

-(void) addTable: (GeoPackageTableMapData *) table;

-(GeoPackageTableMapData *) getTable: (NSString *) name;

-(NSArray<GeoPackageTableMapData *> *) getTables;

-(void) removeFromMapView: (MKMapView *) mapView;

@end
