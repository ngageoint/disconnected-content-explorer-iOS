//
//  MapOverlayCellItem.h
//  DICE
//
//  Created by Brian Osborn on 3/2/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 *  Map Overlay Cell item containing the data backing a single row in the overlay table, parent or child level
 */
@interface MapOverlayCellItem : NSObject

/**
 *  Overlay name
 */
@property (nonatomic, strong) NSString * name;

/**
 *  Current activated state
 */
@property (nonatomic) BOOL enabled;

/**
 *  Children overlays when a parent
 */
@property (nonatomic, strong) NSMutableArray<MapOverlayCellItem *> * children;

/**
 *  False when a parent, true when a child
 */
@property (nonatomic) BOOL child;

/**
 *  Parent overlay when a child
 */
@property (nonatomic, strong) MapOverlayCellItem * parent;

/**
 *  True if a tiles table
 */
@property (nonatomic) BOOL tiles;

/**
 *  True if a features table
 */
@property (nonatomic) BOOL features;

/**
 *  Count of data in the overlay
 */
@property (nonatomic) NSInteger count;

/**
 *  Minimum zoom level for the overlay
 */
@property (nonatomic) NSInteger minZoom;

/**
 *  Maximum zoom level for the overlay
 */
@property (nonatomic) NSInteger maxZoom;

/**
 *  Linked overlays
 */
@property (nonatomic, strong) NSMutableArray<MapOverlayCellItem *> * linked;

/**
 *  True if a locked overlay that can not be deleted
 */
@property (nonatomic) BOOL locked;

/**
 *  Initializer for a top level overlay
 *
 *  @param name cache name
 *
 *  @return new instance
 */
- (id)initWithName: (NSString *) name;

/**
 *  Initializer for a tile table child overlay
 *
 *  @param parent    parent cache
 *  @param tileTable tile table name
 *
 *  @return new instance
 */
- (id)initWithParent: (MapOverlayCellItem *) parent andTileTable: (NSString *) tileTable;

/**
 *  Initializer for a feature table child overlay
 *
 *  @param parent       parent cache
 *  @param featureTable feature  table name
 *
 *  @return new instance
 */
- (id)initWithParent: (MapOverlayCellItem *) parent andFeatureTable: (NSString *) featureTable;

/**
 *  Get the information about the overlay
 *
 *  @return information string
 */
- (NSString *) getInfo;

/**
 *  Get the icon image name to display for this overlay
 *
 *  @return icon image name
 */
- (NSString *) getIconImageName;

@end
