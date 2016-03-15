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
#import "GPKGFeatureTableData.h"

/**
 *  Map data managed for a single GeoPackage table
 */
@interface GeoPackageTableMapData : NSObject

/**
 *  Bounded overlay added to the map view
 */
@property (nonatomic, strong) GPKGBoundedOverlay * boundedOverlay;

/**
 *  Feature overlay queries for handling map click queries
 */
@property (nonatomic, strong) NSMutableArray<GPKGFeatureOverlayQuery *> * featureOverlayQueries;

/**
 *  Map shapes added to the map view
 */
@property (nonatomic, strong) NSMutableArray<GPKGMapShape *> * mapShapes;

/**
 *  Initializer
 *
 *  @param name table name
 *
 *  @return new instance
 */
-(id) initWithName: (NSString *) name;

/**
 *  Get the GeoPackage table name
 *
 *  @return table name
 */
-(NSString *) getName;

/**
 *  Add a feature overlay query to the table
 *
 *  @param query feature overlay query
 */
-(void) addFeatureOverlayQuery: (GPKGFeatureOverlayQuery *) query;

/**
 *  Add a map shape to the table
 *
 *  @param shape map shape
 */
-(void) addMapShape: (GPKGMapShape *) shape;

/**
 *  Remove the GeoPackage table from the map view
 *
 *  @param mapView map view
 */
-(void) removeFromMapView: (MKMapView *) mapView;

/**
 *  Query and build a map click location message from GeoPackage table
 *
 *  @param locationCoordinate click location
 *  @param mapView map view
 *
 *  @return click message
 */
-(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andMap: (MKMapView *) mapView;

/**
 *  Query and build a map click location message from GeoPackage table
 *
 *  @param locationCoordinate click location
 *  @param zoom               zoom level
 *  @param mapBounds          map bounds
 *
 *  @return click message
 */
-(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds: (GPKGBoundingBox *) mapBounds;

/**
 *  Query and build map click table data from GeoPackage table
 *
 *  @param locationCoordinate click location
 *  @param mapView            map view
 *
 *  @return click table data
 */
-(GPKGFeatureTableData *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andMap: (MKMapView *) mapView;

/**
 *  Query and build map click table data from GeoPackage table
 *
 *  @param locationCoordinate click location
 *  @param zoom               zoom level
 *  @param mapBounds          map bounds
 *
 *  @return click table data
 */
-(GPKGFeatureTableData *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds: (GPKGBoundingBox *) mapBounds;

@end
