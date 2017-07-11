//
//  DICEConstants.h
//  DICE
//
//  Created by Brian Osborn on 2/23/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const DICE_REPORT_SHARED_DIRECTORY;
FOUNDATION_EXPORT NSString * const DICE_SELECTED_CACHES;
FOUNDATION_EXPORT NSString * const DICE_SELECTED_CACHES_UPDATED;
FOUNDATION_EXPORT NSString * const DICE_ZOOM_TO_REPORTS;
FOUNDATION_EXPORT NSString * const DICE_TEMP_CACHE_PREFIX;
FOUNDATION_EXPORT NSInteger const DICE_CACHE_FEATURE_TILES_MAX_POINTS_PER_TILE;
FOUNDATION_EXPORT NSInteger const DICE_CACHE_FEATURE_TILES_MAX_FEATURES_PER_TILE;
FOUNDATION_EXPORT NSInteger const DICE_CACHE_FEATURES_MAX_POINTS_PER_TABLE;
FOUNDATION_EXPORT NSInteger const DICE_CACHE_FEATURES_MAX_FEATURES_PER_TABLE;
FOUNDATION_EXPORT NSInteger const DICE_FEATURES_MAX_ZOOM;
FOUNDATION_EXPORT NSInteger const DICE_FEATURE_TILES_MIN_ZOOM_OFFSET;

#pragma mark - errors
FOUNDATION_EXPORT NSString * const DICEPersistenceErrorDomain;

typedef NS_ENUM(NSUInteger, DICEPersistenceErrorCode) {
    DICEInvalidSourceUrlErrorCode,
    DICEInvalidImportDirErrorCode,
    DICEInvalidBaseDirErrorCode,
    DICEInvalidRootFileErrorCode,
    DICEInvalidThumbnailErrorCode,
};

@interface DICEConstants : NSObject

@end
