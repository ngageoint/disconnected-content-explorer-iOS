//
//  ReportMetaData.m
//  DICE
//
//  Created by Robert St. John on 8/5/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "ParseJsonOperation.h"


@implementation ParseJsonOperation

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keys = [super keyPathsForValuesAffectingValueForKey:key];

    if ([@"ready" isEqualToString:key]) {
        keys = [keys setByAddingObject:NSStringFromSelector(@selector(jsonFileUrl))];
    }

    return keys;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return nil;
    }

    return self;
}

- (BOOL)isReady
{
    return self.jsonUrl != nil && super.ready;
}

- (void)setJsonUrl:(NSURL *)jsonFileUrl
{
    if (self.executing) {
        [NSException raise:@"IllegalStateException" format:@"cannot change jsonFileUrl after ParseReportMetaDataOperation has started"];
    }

    _jsonUrl = jsonFileUrl;
}

- (void)main
{
    @autoreleasepool {
        // TODO: do it
    }
}

@end
