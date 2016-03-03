//
//  MapOverlayActiveSwitch.h
//  DICE
//
//  Created by Brian Osborn on 3/2/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MapOverlayCellItem.h"

/**
 *  Map overlay active switch on table cells
 */
@interface MapOverlayActiveSwitch : UISwitch

@property (nonatomic, strong) MapOverlayCellItem * overlay;

@end
