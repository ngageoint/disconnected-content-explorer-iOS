//
//  GeoPackageMapOverlays.h
//  DICE
//
//  Created by Brian Osborn on 2/23/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>

@interface GeoPackageMapOverlays : NSObject

-(id) initWithMapView: (MKMapView *) mapView;

-(void) updateMap;

@end
