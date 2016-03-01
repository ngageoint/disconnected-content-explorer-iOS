//
//  GeoPackageMapData.m
//  DICE
//
//  Created by Brian Osborn on 2/29/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "GeoPackageMapData.h"

@interface GeoPackageMapData()
    @property (nonatomic, strong) NSString * name;
    @property (nonatomic, strong) NSMutableDictionary<NSString *, GeoPackageTableMapData *> * tableData;
@end

@implementation GeoPackageMapData

-(id) initWithName: (NSString *) name{
    if (self = [super init]) {
        self.name = name;
        self.tableData = [[NSMutableDictionary alloc] init];
    }
    
    return self;
}

-(NSString *) getName{
    return self.name;
}

-(void) addTable: (GeoPackageTableMapData *) table{
    [self.tableData setObject:table forKey:[table getName]];
}

-(GeoPackageTableMapData *) getTable: (NSString *) name{
    return [self.tableData objectForKey:name];
}

-(NSArray<GeoPackageTableMapData *> *) getTables{
    return [self.tableData allValues];
}

-(void) removeFromMapView: (MKMapView *) mapView{
    for(GeoPackageTableMapData * table in [self.tableData allValues]){
        [table removeFromMapView:mapView];
    }
}

@end
