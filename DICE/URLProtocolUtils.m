//
//  URLProtocolUtils.m
//  DICE
//
//  Created by Brian Osborn on 3/8/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "URLProtocolUtils.h"

@implementation URLProtocolUtils

+ (NSDictionary<NSString *, NSArray *> *) parseQueryFromUrl: (NSURL *) url {
    
    NSString * queryString = url.query;
    NSDictionary<NSString *, NSArray *> * query = [self parseQuery:queryString];
    
    return query;
}

+ (NSDictionary<NSString *, NSArray *> *) parseQuery: (NSString *) query {
    NSMutableDictionary<NSString *, NSMutableArray *> *queryComponents = [NSMutableDictionary dictionary];
    for(NSString *keyValue in [query componentsSeparatedByString:@"&"]) {
        NSArray *keyValueArray = [keyValue componentsSeparatedByString:@"="];
        if ([keyValueArray count] < 2) continue;
        NSString *key = [self decodeUrl:[keyValueArray objectAtIndex:0]];
        NSString *value = [self decodeUrl:[keyValueArray objectAtIndex:1]];
        NSMutableArray *results = [queryComponents objectForKey:key];
        if(!results){
            results = [NSMutableArray arrayWithCapacity:1];
            [queryComponents setObject:results forKey:key];
        }
        [results addObject:value];
    }
    return queryComponents;
}

+ (NSString *)decodeUrl: (NSString *) urlString {
    NSString *result = [urlString stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    result = [result stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    return result;
}

@end
