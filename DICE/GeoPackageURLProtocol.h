//
//  GeoPackageURLProtocol.h
//  DICE
//
//  Created by Brian Osborn on 3/7/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GeoPackageURLProtocol : NSURLProtocol

/**
 *  Start and register the GeoPackage URL Protocol
 */
+ (void)start;

+ (void) startCache: (NSString *) id;

+ (void) closeCache;

+(NSString *) reportIdPrefixWithReport: (NSString *) report;

+(NSString *) reportIdPrefixWithName: (NSString *) name andReport: (NSString *) report andShare: (BOOL) share;

@end
