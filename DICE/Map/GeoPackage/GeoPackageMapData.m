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

-(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andMap: (MKMapView *) mapView{
    NSMutableString * clickMessage = [[NSMutableString alloc] init];
    for(GeoPackageTableMapData * tableMapData in [self.tableData allValues]){
        NSString * message = [tableMapData mapClickMessageWithLocationCoordinate:locationCoordinate andMap:mapView];
        if(message != nil){
            if([clickMessage length] > 0){
                [clickMessage appendString:@"\n\n"];
            }
            [clickMessage appendString:message];
        }
    }
    return [clickMessage length] > 0 ? clickMessage : nil;
}

-(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds: (GPKGBoundingBox *) mapBounds{
    NSMutableString * clickMessage = [[NSMutableString alloc] init];
    for(GeoPackageTableMapData * tableMapData in [self.tableData allValues]){
        NSString * message = [tableMapData mapClickMessageWithLocationCoordinate:locationCoordinate andZoom:zoom andMapBounds:mapBounds];
        if(message != nil){
            if([clickMessage length] > 0){
                [clickMessage appendString:@"\n\n"];
            }
            [clickMessage appendString:message];
        }
    }
    return [clickMessage length] > 0 ? clickMessage : nil;
}

-(NSDictionary *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andMap: (MKMapView *) mapView{
    NSMutableDictionary * clickData = [[NSMutableDictionary alloc] init];
    for(GeoPackageTableMapData * tableMapData in [self.tableData allValues]){
        GPKGFeatureTableData * tableData = [tableMapData mapClickTableDataWithLocationCoordinate:locationCoordinate andMap:mapView];
        if(tableData != nil){
            [clickData setObject:[tableData jsonCompatible] forKey:[tableData getName]];
        }
    }
    
    return clickData.count > 0 ? clickData : nil;
}

-(NSDictionary *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds: (GPKGBoundingBox *) mapBounds{
    NSMutableDictionary * clickData = [[NSMutableDictionary alloc] init];
    for(GeoPackageTableMapData * tableMapData in [self.tableData allValues]){
        GPKGFeatureTableData * tableData = [tableMapData mapClickTableDataWithLocationCoordinate:locationCoordinate andZoom:zoom andMapBounds:mapBounds];
        if(tableData != nil){
            [clickData setObject:[tableData jsonCompatible] forKey:[tableData getName]];
        }
    }
    
    return clickData.count > 0 ? clickData : nil;
}

@end
