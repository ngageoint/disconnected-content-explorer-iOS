//
//  GeoPackageMapOverlays.m
//  DICE
//
//  Created by Brian Osborn on 2/23/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "GeoPackageMapOverlays.h"
#import "GPKGGeoPackageFactory.h"
#import "GPKGGeoPackageCache.h"
#import "GPKGOverlayFactory.h"
#import "GPKGFeatureTileTableLinker.h"
#import "GPKGFeatureTiles.h"
#import "GPKGFeatureOverlay.h"
#import "GPKGNumberFeaturesTile.h"
#import "GPKGFeatureOverlayQuery.h"
#import "GPKGMapShapeConverter.h"

@interface GeoPackageMapOverlays()
    @property (nonatomic, strong) MKMapView *mapView;
    @property (nonatomic, strong) GPKGGeoPackageManager * manager;
    @property (nonatomic, strong) GPKGGeoPackageCache *cache;
@end

@implementation GeoPackageMapOverlays

-(id) initWithMapView: (MKMapView *) mapView{
    if (self = [super init]) {
        self.mapView = mapView;
        self.manager = [GPKGGeoPackageFactory getManager];
        self.cache = [[GPKGGeoPackageCache alloc]initWithManager:self.manager];
    }
    
    return self;
}

-(void) updateMap{
    
    // Add the GeoPackage caches
    NSArray * geoPackages = [self.manager databases];
    for(NSString * geoPackage in geoPackages){
        
        // Make sure the GeoPackage file exists
        NSString * filePath = [self.manager documentsPathForDatabase:geoPackage];
        if(filePath != nil && [[NSFileManager defaultManager] fileExistsAtPath:filePath]){
            
            [self addGeoPackageWithName:geoPackage];
            
        }else{
            // Delete if the file was deleted
            [self.manager delete:geoPackage];
        }
    }

}

-(void) addGeoPackageWithName: (NSString *) name{
    
    GPKGGeoPackage * geoPackage = [self.cache getOrOpen:name];
    
    for(NSString * tileTable in [geoPackage getTileTables]){
        [self addTileTableWithGeoPackage:geoPackage andName:tileTable];
    }
    
    for(NSString * featureTable in [geoPackage getFeatureTables]){
        [self addFeatureTableWithGeoPackage:geoPackage andName:featureTable];
    }
    
}

-(void) addTileTableWithGeoPackage: (GPKGGeoPackage *) geoPackage andName: (NSString *) name{
    
    // Create a new GeoPackage tile provider and add to the map
    GPKGTileDao * tileDao = [geoPackage getTileDaoWithTableName:name];
    GPKGBoundedOverlay * geoPackageTileOverlay = [GPKGOverlayFactory getBoundedOverlay:tileDao];
    geoPackageTileOverlay.canReplaceMapContent = false;
    
    // Check for linked feature tables
    GPKGFeatureTileTableLinker * linker = [[GPKGFeatureTileTableLinker alloc] initWithGeoPackage:geoPackage];
    NSArray<GPKGFeatureDao *> * featureDaos = [linker getFeatureDaosForTileTable:tileDao.tableName];
    for(GPKGFeatureDao * featureDao in featureDaos){
        
        // Create the feature tiles
        GPKGFeatureTiles * featureTiles = [[GPKGFeatureTiles alloc] initWithFeatureDao:featureDao];
        
        // Create an index manager
        GPKGFeatureIndexManager * indexer = [[GPKGFeatureIndexManager alloc] initWithGeoPackage:geoPackage andFeatureDao:featureDao];
        [featureTiles setIndexManager:indexer];
        
        // Add the feature overlay query
        GPKGFeatureOverlayQuery * featureOverlayQuery = [[GPKGFeatureOverlayQuery alloc] initWithBoundedOverlay:geoPackageTileOverlay andFeatureTiles:featureTiles];
        // TODO maintain the feature overlay query
    }
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self.mapView addOverlay:geoPackageTileOverlay level:MKOverlayLevelAboveLabels];
    });
    
}

-(void) addFeatureTableWithGeoPackage: (GPKGGeoPackage *) geoPackage andName: (NSString *) name{
    
    // Create a new GeoPackage tile provider and add to the map
    GPKGFeatureDao * featureDao = [geoPackage getFeatureDaoWithTableName:name];
    
    GPKGFeatureIndexManager * indexer = [[GPKGFeatureIndexManager alloc] initWithGeoPackage:geoPackage andFeatureDao:featureDao];
    
    if([indexer isIndexed]){
        GPKGFeatureTiles * featureTiles = [[GPKGFeatureTiles alloc] initWithFeatureDao:featureDao];
        int maxFeaturesPerTile = 0;
        if([featureDao getGeometryType] == WKB_POINT){
            maxFeaturesPerTile = 1000; // TODO
        }else{
            maxFeaturesPerTile = 500; // TODO
        }
        [featureTiles setMaxFeaturesPerTile:[NSNumber numberWithInt:maxFeaturesPerTile]];
        GPKGNumberFeaturesTile * numberFeaturesTile = [[GPKGNumberFeaturesTile alloc] init];
        // Adjust the max features number tile draw paint attributes here as needed to
        // change how tiles are drawn when more than the max features exist in a tile
        [featureTiles setMaxFeaturesTileDraw:numberFeaturesTile];
        [featureTiles setIndexManager:[[GPKGFeatureIndexManager alloc] initWithGeoPackage:geoPackage andFeatureDao:featureDao]];
        // Adjust the feature tiles draw paint attributes here as needed to change how
        // features are drawn on tiles
        GPKGFeatureOverlay * featureOverlay = [[GPKGFeatureOverlay alloc] initWithFeatureTiles:featureTiles];
        [featureOverlay setMinZoom:[NSNumber numberWithInt:[featureDao getZoomLevel]]];
        
        GPKGFeatureTileTableLinker * linker = [[GPKGFeatureTileTableLinker alloc] initWithGeoPackage:geoPackage];
        NSArray<GPKGTileDao *> * tileDaos = [linker getTileDaosForFeatureTable:featureDao.tableName];
        [featureOverlay ignoreTileDaos:tileDaos];
        
        GPKGFeatureOverlayQuery * featureOverlayQuery = [[GPKGFeatureOverlayQuery alloc] initWithFeatureOverlay:featureOverlay];
        // TODO maintain the feature overlay query
        
        featureOverlay.canReplaceMapContent = false;
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self.mapView addOverlay:featureOverlay level:MKOverlayLevelAboveLabels];
        });
    }else{
        int maxFeaturesPerTable = 0;
        if([featureDao getGeometryType] == WKB_POINT){
            maxFeaturesPerTable = 1000; // TODO
        }else{
            maxFeaturesPerTable = 500; // TODO
        }
        GPKGProjection * projection = featureDao.projection;
        GPKGMapShapeConverter * shapeConverter = [[GPKGMapShapeConverter alloc] initWithProjection:projection];
        GPKGResultSet * resultSet = [featureDao queryForAll];
        @try {
            int totalCount = [resultSet count];
            int count = 0;
            while([resultSet moveToNext]){
                GPKGFeatureRow * featureRow = [featureDao getFeatureRow:resultSet];
                GPKGGeometryData * geometryData = [featureRow getGeometry];
                if(geometryData != nil && !geometryData.empty){
                    WKBGeometry * geometry = geometryData.geometry;
                    if(geometry != nil){
                        GPKGMapShape * shape = [shapeConverter toShapeWithGeometry:geometry];
                        dispatch_sync(dispatch_get_main_queue(), ^{
                            [GPKGMapShapeConverter addMapShape:shape toMapView:self.mapView];
                        });
                        
                        if(++count >= maxFeaturesPerTable){
                            if(count < totalCount){
                                NSLog(@"%@-%@- added %d of %d", geoPackage.name, name, count, totalCount);
                            }
                            break;
                        }
                    }
                }
            }
        }
        @finally {
            [resultSet close];
        }
    }
    
}

@end
