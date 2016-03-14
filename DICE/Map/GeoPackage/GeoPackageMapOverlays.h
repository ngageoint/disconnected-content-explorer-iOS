//
//  GeoPackageMapOverlays.h
//  DICE
//
//  Created by Brian Osborn on 2/23/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "Report.h"

/**
 *  Manages GeoPackage feature and tile overlays, including adding to and removing from the map
 */
@interface GeoPackageMapOverlays : NSObject

/**
 *  Initializer
 *
 *  @param mapView map view
 *
 *  @return new instance
 */
-(id) initWithMapView: (MKMapView *) mapView;

/**
 *  Determine if there are any GeoPackages within DICE
 *
 *  @return true if GeoPackages exist
 */
-(BOOL) hasGeoPackages;

/**
 *  Update the map with selected GeoPackages
 */
-(void) updateMap;

/**
 *  Query and build a map click location message from enabled GeoPackage tables
 *
 *  @param locationCoordinate click location
 *
 *  @return click message
 */
-(NSString *) onMapClickWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate;

/**
 *  Report has been selected on the map
 *
 *  @param report selected report
 */
-(void) selectedReport: (Report *) report;

/**
 *  Report has been deselected on the map
 *
 *  @param reportCache deselected report
 */
-(void) deselectedReport: (Report *) report;

@end
