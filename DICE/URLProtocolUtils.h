//
//  URLProtocolUtils.h
//  DICE
//
//  Created by Brian Osborn on 3/8/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface URLProtocolUtils : NSObject

+ (NSDictionary *)parseQueryFromUrl: (NSURL *) url;

+ (NSDictionary *)parseQuery: (NSString *) query;

+ (NSString *)decodeUrl: (NSString *) urlString;

@end
