//
//  GeoPackageMapData.h
//  DICE
//
//  Created by Brian Osborn on 2/29/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GeoPackageTableMapData.h"

/**
 *  Map data managed for a single GeoPackage
 */
@interface GeoPackageMapData : NSObject

/**
 *  Initializer
 *
 *  @param name GeoPackage name
 *
 *  @return new instance
 */
-(id) initWithName: (NSString *) name;

/**
 *  Get the GeoPackage name
 *
 *  @return name
 */
-(NSString *) getName;

/**
 *  Add a table to the GeoPackage
 *
 *  @param table GeoPackage table
 */
-(void) addTable: (GeoPackageTableMapData *) table;

/**
 *  Get the table map data from the table name
 *
 *  @param name table name
 *
 *  @return table map data
 */
-(GeoPackageTableMapData *) getTable: (NSString *) name;

/**
 *  Get all GeoPackage table map data
 *
 *  @return array of table map data
 */
-(NSArray<GeoPackageTableMapData *> *) getTables;

/**
 *  Remove the GeoPackage from the map view
 *
 *  @param mapView map view
 */
-(void) removeFromMapView: (MKMapView *) mapView;

/**
 *  Query and build a map click location message from the GeoPackage
 *
 *  @param locationCoordinate click location
 *  @param mapView map view
 *
 *  @return click message
 */
-(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andMap: (MKMapView *) mapView;

/**
 *  Query and build a map click location message from the GeoPackage
 *
 *  @param locationCoordinate click location
 *  @param zoom               zoom level
 *  @param mapBounds          map bounds
 *
 *  @return click message
 */
-(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds: (GPKGBoundingBox *) mapBounds;

/**
 *  Query a build a map click location array of table data from the GeoPackage
 *
 *  @param locationCoordinate click location
 *  @param mapView            map view
 *
 *  @return click array of table data
 */
-(NSDictionary *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andMap: (MKMapView *) mapView;

/**
 *  Query a build a map click location array of table data from the GeoPackage
 *
 *  @param locationCoordinate click location
 *  @param zoom               zoom level
 *  @param mapBounds          map bounds
 *
 *  @return click array of table data
 */
-(NSDictionary *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds: (GPKGBoundingBox *) mapBounds;

@end
