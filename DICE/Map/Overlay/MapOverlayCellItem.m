//
//  MapOverlayCellItem.m
//  DICE
//
//  Created by Brian Osborn on 3/2/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "MapOverlayCellItem.h"

@implementation MapOverlayCellItem

- (id)initWithName: (NSString *) name{
    self = [super init];
    if(self){
        self.name = name;
        self.children = [[NSMutableArray alloc] init];
    }
    
    return self;
}

- (id)initWithParent: (MapOverlayCellItem *) parent andTileTable: (NSString *) tileTable{
    self = [super init];
    if(self){
        self.parent = parent;
        self.name = tileTable;
        self.child = YES;
        self.tiles = YES;
    }
    
    return self;
}

- (id)initWithParent: (MapOverlayCellItem *) parent andFeatureTable: (NSString *) featureTable{
    self = [super init];
    if(self){
        self.parent = parent;
        self.name = featureTable;
        self.child = YES;
        self.features = YES;
        self.linked = [[NSMutableArray alloc] init];
    }
    
    return self;
}

-(void) setEnabled:(BOOL)enabled{
    _enabled = enabled;
    if(self.linked != nil){
        for(MapOverlayCellItem * linkedTable in self.linked){
            [linkedTable setEnabled:enabled];
        }
    }
}

- (NSString *) getInfo{
    NSString * type = nil;
    if(self.tiles){
        type = @"tiles";
    }else if(self.features){
        type = @"features";
    }else{
        type = @"GeoPackage";
    }
    int minZoom = (int)self.minZoom;
    int maxZoom = (int)self.maxZoom;
    if(self.linked != nil){
        for(MapOverlayCellItem * linkedTable in self.linked){
            minZoom = MIN(minZoom, (int)linkedTable.minZoom);
            maxZoom = MAX(maxZoom, (int)linkedTable.maxZoom);
        }
    }
    return [NSString stringWithFormat:@"%@: %ld, zoom: %d - %d", type,(long)self.count, minZoom, maxZoom];
}

- (NSString *) getIconImageName{
    NSString * icon = nil;
    if(self.tiles){
        icon = @"layers";
    }else if(self.features){
        icon = @"features";
    }else{
        icon = @"geopackage";
    }
    return icon;
}

@end
