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
#import "GeoPackageMapData.h"
#import "DICEConstants.h"

@interface GeoPackageMapOverlays()
    @property (nonatomic, strong) MKMapView *mapView;
    @property (nonatomic, strong) GPKGGeoPackageManager * manager;
    @property (nonatomic, strong) GPKGGeoPackageCache *cache;
    @property (nonatomic, strong) NSMutableDictionary<NSString *, GeoPackageMapData *> *mapData;
@end

@implementation GeoPackageMapOverlays

-(id) initWithMapView: (MKMapView *) mapView{
    if (self = [super init]) {
        self.mapView = mapView;
        self.manager = [GPKGGeoPackageFactory getManager];
        self.cache = [[GPKGGeoPackageCache alloc]initWithManager:self.manager];
        self.mapData = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

-(void) updateMap{
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary * selectedCaches = [[defaults objectForKey:DICE_SELECTED_CACHES] mutableCopy];
    
    NSMutableDictionary<NSString *, GeoPackageMapData *> *newMapData = [[NSMutableDictionary alloc] init];
    
    if(selectedCaches != nil){
    
        // Add the GeoPackage caches
        for(NSString * name in [selectedCaches allKeys]){
            
            BOOL deleteFromSelected = YES;
            
            // Make sure the GeoPackage exists
            if([self.manager exists:name]){
            
                // Make sure the GeoPackage file exists
                NSString * filePath = [self.manager documentsPathForDatabase:name];
                if(filePath != nil && [[NSFileManager defaultManager] fileExistsAtPath:filePath]){
                    
                    deleteFromSelected = NO;
                    
                    NSMutableArray * selected = [[selectedCaches objectForKey:name] mutableCopy];
                    
                    // Close a previously open GeoPackage connection if a new GeoPackage version
                    if([selected count] == 0){
                        [self.cache close:name];
                    }
                    
                    GPKGGeoPackage * geoPackage = [self.cache getOrOpen:name];
                    
                    GeoPackageMapData * existingGeoPackageData = [self.mapData objectForKey:name];
                    
                    // If the GeoPackage is selected with no tables, select all of them as it is a new version
                    if([selected count] == 0){
                        [selected addObjectsFromArray:[geoPackage getTables]];
                        [selectedCaches setObject:selected forKey:name];
                        [defaults setObject:selectedCaches forKey:DICE_SELECTED_CACHES];
                        [defaults synchronize];
                        
                        if(existingGeoPackageData != nil){
                            [existingGeoPackageData removeFromMapView:self.mapView];
                            existingGeoPackageData = nil;
                        }
                    }
                    
                    GeoPackageMapData * geoPackageData = [[GeoPackageMapData alloc] initWithName:geoPackage.name];
                    [newMapData setObject:geoPackageData forKey:geoPackage.name];
                    
                    [self addGeoPackage:geoPackage andSelected:selected andData:geoPackageData andExistingData:existingGeoPackageData];
                    
                }else{
                    // Delete if the file was deleted
                    [self.manager delete:name];
                }
            }
            
            // Remove the GeoPackage from the list of selected
            if(deleteFromSelected){
                [selectedCaches removeObjectForKey:name];
                [defaults setObject:selectedCaches forKey:DICE_SELECTED_CACHES];
                [defaults synchronize];
            }
        }
        
    }

    // Remove GeoPackage tables from the map that are no longer selected
    for(GeoPackageMapData * oldGeoPackageMapData in [self.mapData allValues]){
        
        GeoPackageMapData * newGeoPackageMapData = [newMapData objectForKey:[oldGeoPackageMapData getName]];
        if(newGeoPackageMapData == nil){
            [oldGeoPackageMapData removeFromMapView:self.mapView];
            [self.cache close:[oldGeoPackageMapData getName]];
        }else{
            
            for(GeoPackageTableMapData * oldGeoPackageTableMapData in [oldGeoPackageMapData getTables]){
                
                GeoPackageTableMapData * newGeoPackageTableMapData = [newGeoPackageMapData getTable:[oldGeoPackageTableMapData getName]];
                
                if(newGeoPackageTableMapData == nil){
                    [oldGeoPackageTableMapData removeFromMapView:self.mapView];
                }
            }
            
        }
        
    }
    
    self.mapData = newMapData;
}

-(void) addGeoPackage: (GPKGGeoPackage *) geoPackage andSelected: (NSMutableArray *) selected andData: (GeoPackageMapData *) data andExistingData: (GeoPackageMapData *) existingData{
    
    for(NSString * table in selected){
        
        BOOL addNew = true;
        
        if(existingData != nil){
            GeoPackageTableMapData * tableData = [existingData getTable:table];
            if(tableData != nil){
                addNew = false;
                [data addTable:tableData];
            }
        }
        
        if(addNew){
            if([geoPackage isTileTable:table]){
                [self addTileTableWithGeoPackage:geoPackage andName:table andData:data];
            } else if([geoPackage isFeatureTable:table]){
                [self addFeatureTableWithGeoPackage:geoPackage andName:table andData:data];
            }
        }
        
    }
    
}

-(void) addTileTableWithGeoPackage: (GPKGGeoPackage *) geoPackage andName: (NSString *) name andData: (GeoPackageMapData *) data{
    
    GeoPackageTableMapData * tableData = [[GeoPackageTableMapData alloc] initWithName:name];
    [data addTable:tableData];
    
    // Create a new GeoPackage tile provider and add to the map
    GPKGTileDao * tileDao = [geoPackage getTileDaoWithTableName:name];
    GPKGBoundedOverlay * geoPackageTileOverlay = [GPKGOverlayFactory getBoundedOverlay:tileDao];
    [tableData setBoundedOverlay:geoPackageTileOverlay];
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
        [tableData addFeatureOverlayQuery:featureOverlayQuery];
    }
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self.mapView addOverlay:geoPackageTileOverlay level:MKOverlayLevelAboveRoads];
    });
    
}

-(void) addFeatureTableWithGeoPackage: (GPKGGeoPackage *) geoPackage andName: (NSString *) name andData: (GeoPackageMapData *) data{
    
    GeoPackageTableMapData * tableData = [[GeoPackageTableMapData alloc] initWithName:name];
    [data addTable:tableData];
    
    // Create a new GeoPackage tile provider and add to the map
    GPKGFeatureDao * featureDao = [geoPackage getFeatureDaoWithTableName:name];
    
    GPKGFeatureIndexManager * indexer = [[GPKGFeatureIndexManager alloc] initWithGeoPackage:geoPackage andFeatureDao:featureDao];
    
    if([indexer isIndexed]){
        GPKGFeatureTiles * featureTiles = [[GPKGFeatureTiles alloc] initWithFeatureDao:featureDao];
        int maxFeaturesPerTile = 0;
        if([featureDao getGeometryType] == WKB_POINT){
            maxFeaturesPerTile = (int)DICE_CACHE_FEATURE_TILES_MAX_POINTS_PER_TILE;
        }else{
            maxFeaturesPerTile = (int)DICE_CACHE_FEATURE_TILES_MAX_FEATURES_PER_TILE;
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
        [tableData setBoundedOverlay:featureOverlay];
        [featureOverlay setMinZoom:[NSNumber numberWithInt:[featureDao getZoomLevel]]];
        
        GPKGFeatureTileTableLinker * linker = [[GPKGFeatureTileTableLinker alloc] initWithGeoPackage:geoPackage];
        NSArray<GPKGTileDao *> * tileDaos = [linker getTileDaosForFeatureTable:featureDao.tableName];
        [featureOverlay ignoreTileDaos:tileDaos];
        
        GPKGFeatureOverlayQuery * featureOverlayQuery = [[GPKGFeatureOverlayQuery alloc] initWithFeatureOverlay:featureOverlay];
        [tableData addFeatureOverlayQuery:featureOverlayQuery];
        
        featureOverlay.canReplaceMapContent = false;
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self.mapView addOverlay:featureOverlay level:MKOverlayLevelAboveLabels];
        });
    }else{
        int maxFeaturesPerTable = 0;
        if([featureDao getGeometryType] == WKB_POINT){
            maxFeaturesPerTable = (int)DICE_CACHE_FEATURES_MAX_POINTS_PER_TABLE;
        }else{
            maxFeaturesPerTable = (int)DICE_CACHE_FEATURES_MAX_FEATURES_PER_TABLE;
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
                        [tableData addMapShape:shape];
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
