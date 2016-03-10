//
//  MapOverlayController.m
//  DICE
//
//  Created by Brian Osborn on 3/2/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "MapOverlayController.h"
#import "MapOverlayTableCell.h"
#import "MapOverlayChildTableCell.h"
#import "DICEConstants.h"
#import "GPKGGeoPackageFactory.h"
#import "MapOverlayCellItem.h"
#import "GPKGFeatureTileTableLinker.h"
#import "GPKGFeatureIndexManager.h"

@interface MapOverlayController ()

@property (nonatomic, strong) GPKGGeoPackageManager * manager;
@property (nonatomic, strong) NSMutableArray<MapOverlayCellItem *> *tableCells;

@end

static NSMutableSet<NSString *> *expanded;

@implementation MapOverlayController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.manager = [GPKGGeoPackageFactory getManager];
    if(expanded == nil){
        expanded = [[NSMutableSet alloc] init];
    }
}

-(void) viewWillAppear:(BOOL) animated {
    [super viewWillAppear:animated];
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.tableView.layoutMargins = UIEdgeInsetsZero;
    
    [self update];
}

-(void) updateAndReloadData{
    [self update];
    [self.tableView reloadData];
}

-(void) update{
    self.tableCells = [[NSMutableArray alloc] init];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary * selectedCaches = [self getSelectedCachesWithDefaults:defaults];
    
    GPKGGeoPackageManager * manager = [GPKGGeoPackageFactory getManager];
    
    for(NSString * name in [manager databases]){
        MapOverlayCellItem * cellItem = [[MapOverlayCellItem alloc] initWithName:name];
        NSArray * selectedTables = [selectedCaches objectForKey:name];
        if(selectedTables != nil){
            cellItem.enabled = YES;
        }
        [self.tableCells addObject:cellItem];
        if([expanded containsObject:name]){
            GPKGGeoPackage * geoPackage = [manager open:name];
            
            // GeoPackage tile tables, build a mapping between table name and the created map overlays
            NSMutableDictionary<NSString *, MapOverlayCellItem *> * tileMapOverlays = [[NSMutableDictionary alloc] init];
            NSArray * tileTables = [geoPackage getTileTables];
            for(NSString * tileTable in tileTables){
                GPKGTileDao * tileDao = [geoPackage getTileDaoWithTableName:tileTable];
                MapOverlayCellItem * childCellItem = [[MapOverlayCellItem alloc] initWithParent:cellItem andTileTable:tileTable];
                if(cellItem.enabled && ([selectedTables count] == 0 || [selectedTables containsObject:tileTable])){
                    childCellItem.enabled = YES;
                }
                childCellItem.count = [tileDao count];
                childCellItem.minZoom = tileDao.minZoom;
                childCellItem.maxZoom = tileDao.maxZoom;
                [tileMapOverlays setObject:childCellItem forKey:tileTable];
            }
            
            // Get a linker to find tile tables linked to features
            GPKGFeatureTileTableLinker * linker = [[GPKGFeatureTileTableLinker alloc] initWithGeoPackage:geoPackage];
            NSMutableDictionary<NSString *, MapOverlayCellItem *> * linkedTileMapOverlays = [[NSMutableDictionary alloc] init];
            
            // GeoPackage feature tables
            NSArray * featureTables = [geoPackage getFeatureTables];
            for(NSString * featureTable in featureTables){
                GPKGFeatureDao * featureDao = [geoPackage getFeatureDaoWithTableName:featureTable];
                GPKGFeatureIndexManager * indexer = [[GPKGFeatureIndexManager alloc] initWithGeoPackage:geoPackage andFeatureDao:featureDao];
                BOOL indexed = [indexer isIndexed];
                int minZoom = 0;
                if(indexed){
                    minZoom = [featureDao getZoomLevel] + (int)DICE_FEATURE_TILES_MIN_ZOOM_OFFSET;
                    minZoom = MAX(minZoom, 0);
                    minZoom = MIN(minZoom, (int)DICE_FEATURES_MAX_ZOOM);
                }
                MapOverlayCellItem * childCellItem = [[MapOverlayCellItem alloc] initWithParent:cellItem andFeatureTable:featureTable];
                [cellItem.children addObject:childCellItem];
                if(cellItem.enabled && ([selectedTables count] == 0 || [selectedTables containsObject:featureTable])){
                    childCellItem.enabled = YES;
                }
                childCellItem.count = [featureDao count];
                childCellItem.minZoom = minZoom;
                childCellItem.maxZoom = DICE_FEATURES_MAX_ZOOM;
                
                // If indexed, check for linked tile tables
                if(indexed){
                    NSArray<NSString *> * linkedTileTables = [linker getTileTablesForFeatureTable:featureTable];
                    for(NSString * linkedTileTable in linkedTileTables){
                        // Get the tile table cache overlay
                        MapOverlayCellItem * tileCacheOverlay = [tileMapOverlays objectForKey:linkedTileTable];
                        if(tileCacheOverlay != nil){
                            // Remove from tile cache overlays so the tile table is not added as stand alone, and add to the linked overlays
                            [tileMapOverlays removeObjectForKey:linkedTileTable];
                            [linkedTileMapOverlays setObject:tileCacheOverlay forKey:linkedTileTable];
                        }else{
                            // Another feature table may already be linked to this table, so check the linked overlays
                            tileCacheOverlay = [linkedTileMapOverlays objectForKey:linkedTileTable];
                        }
                        
                        // Add the linked tile table to the feature table
                        if(tileCacheOverlay != nil){
                            [childCellItem.linked addObject:tileCacheOverlay];
                        }
                    }
                }
                
                [self.tableCells addObject:childCellItem];
            }
            
            // Add stand alone tile tables that were not linked to feature tables
            for(MapOverlayCellItem * tileCacheOverlay in [tileMapOverlays allValues]){
                [cellItem.children addObject:tileCacheOverlay];
                [self.tableCells addObject:tileCacheOverlay];
            }
            
            [geoPackage close];
        }
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *) tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.tableCells count];;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"Overlays";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCell *cell = nil;
    
    MapOverlayCellItem * tableCell = [self.tableCells objectAtIndex:[indexPath row]];
    
    UIImage * cellImage = nil;
    NSString * typeImage = [tableCell getIconImageName];
    if(typeImage != nil){
        cellImage = [UIImage imageNamed:typeImage];
    }
    
    if(tableCell.child){
        cell = [tableView dequeueReusableCellWithIdentifier:@"childCacheOverlayCell" forIndexPath:indexPath];
        MapOverlayChildTableCell * mapOverlayCell = (MapOverlayChildTableCell *) cell;
        
        [mapOverlayCell.name setText:tableCell.name];
        mapOverlayCell.active.on = tableCell.enabled;
        [mapOverlayCell.info setText:[tableCell getInfo]];
        
        if(cellImage != nil){
            [mapOverlayCell.tableType setImage:cellImage];
        }
        
        [mapOverlayCell.active setOverlay:tableCell];
        
    }else{
        cell = [tableView dequeueReusableCellWithIdentifier:@"cacheOverlayCell" forIndexPath:indexPath];
        MapOverlayTableCell * mapOverlayCell = (MapOverlayTableCell *) cell;
        
        [mapOverlayCell.name setText:tableCell.name];
        mapOverlayCell.active.on = tableCell.enabled;
        
        if(cellImage != nil){
            [mapOverlayCell.tableType setImage:cellImage];
        }
        
        [mapOverlayCell.active setOverlay:tableCell];
    }
        
    cell.layoutMargins = UIEdgeInsetsZero;
    
    return cell;
}

- (void) tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath {
    
    MapOverlayCellItem * tableCell = [self.tableCells objectAtIndex:[indexPath row]];
    if(!tableCell.child){
        if([expanded containsObject:tableCell.name]){
            [expanded removeObject:tableCell.name];
        }else{
            [expanded addObject:tableCell.name];
        }
        [self updateAndReloadData];
    }
    
}

- (IBAction)activeChanged:(MapOverlayActiveSwitch *)sender {
    
    // Update the GeoPackage and all tables to be enabled
    [sender.overlay setEnabled:sender.on];
    for(MapOverlayCellItem * child in sender.overlay.children){
        [child setEnabled:sender.on];
    }
    
    // Update the selected tables
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary * selectedCaches = [self getSelectedCachesWithDefaults:defaults];
    if(sender.on){
        [selectedCaches setObject:[[NSMutableArray alloc] init] forKey:sender.overlay.name];
    }else{
        [selectedCaches removeObjectForKey:sender.overlay.name];
    }
    [self updateSelectedCaches:selectedCaches withDefaults:defaults];
    
    // Reload the table view
    [self.tableView reloadData];
}

- (IBAction)childActiveChanged:(MapOverlayActiveSwitch *)sender {
    
    MapOverlayCellItem * overlay = sender.overlay;
    MapOverlayCellItem * parentOverlay = overlay.parent;
    
    [overlay setEnabled:sender.on];
    
    BOOL parentEnabled = true;
    if(!overlay.enabled){
        parentEnabled = false;
        for(MapOverlayCellItem * childOverlay in parentOverlay.children){
            if(childOverlay.enabled){
                parentEnabled = true;
                break;
            }
        }
    }
    if(parentEnabled != parentOverlay.enabled){
        [parentOverlay setEnabled:parentEnabled];
    }
    
    // Update the selected tables
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary * selectedCaches = [self getSelectedCachesWithDefaults:defaults];
    NSMutableArray * selectedTables = [[selectedCaches objectForKey:parentOverlay.name] mutableCopy];
    if(sender.on){
        if(selectedTables == nil){
            selectedTables = [[NSMutableArray alloc] init];
        }
        [selectedTables addObject:overlay.name];
        for(MapOverlayCellItem * linkedTable in overlay.linked){
            [selectedTables addObject:linkedTable.name];
        }
        [selectedCaches setObject:selectedTables forKey:parentOverlay.name];
    }else if(selectedTables != nil){
        [selectedTables removeObject:overlay.name];
        for(MapOverlayCellItem * linkedTable in overlay.linked){
            [selectedTables removeObject:linkedTable.name];
        }
        if([selectedTables count] == 0){
            [selectedCaches removeObjectForKey:parentOverlay.name];
        }else{
            [selectedCaches setObject:selectedTables forKey:parentOverlay.name];
        }
    }
    [self updateSelectedCaches:selectedCaches withDefaults:defaults];
    
    // Reload the table view
    [self.tableView reloadData];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UITableViewCellEditingStyle style = UITableViewCellEditingStyleNone;
    
    MapOverlayCellItem * tableCell = [self.tableCells objectAtIndex:[indexPath row]];
    if(!tableCell.child){
        style = UITableViewCellEditingStyleDelete;
    }
    
    return style;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    // If row is deleted, delete the GeoPackage
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        MapOverlayCellItem * tableCell = [self.tableCells objectAtIndex:[indexPath row]];
        if(![self.manager delete:tableCell.name]){
            NSLog(@"Error deleting GeoPackage cache file: %@", tableCell.name);
        }else{
            [expanded removeObject:tableCell.name];
            
            // Update the selected tables
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSMutableDictionary * selectedCaches = [self getSelectedCachesWithDefaults:defaults];
            [selectedCaches removeObjectForKey:tableCell.name];
            [self updateSelectedCaches:selectedCaches withDefaults:defaults];
            
            // Update the list data and reload
            [self updateAndReloadData];
        }
        
    }
}

-(NSMutableDictionary *) getSelectedCachesWithDefaults: (NSUserDefaults *) defaults{
     NSMutableDictionary * selectedCaches = [[defaults objectForKey:DICE_SELECTED_CACHES] mutableCopy];
    if(selectedCaches == nil){
        selectedCaches = [[NSMutableDictionary alloc] init];
    }
    return selectedCaches;
}

-(void) updateSelectedCaches: (NSMutableDictionary *) selectedCaches withDefaults: (NSUserDefaults *) defaults{
    [defaults setObject:selectedCaches forKey:DICE_SELECTED_CACHES];
    [defaults setObject:nil forKey:DICE_SELECTED_CACHES_UPDATED];
    [defaults synchronize];
}

@end
