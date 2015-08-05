//
//  ReportMetaData.m
//  DICE
//
//  Created by Robert St. John on 8/5/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "ParseReportMetaDataOperation.h"


@implementation ParseReportMetaDataOperation

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keys = [super keyPathsForValuesAffectingValueForKey:key];

    if ([@"ready" isEqualToString:key]) {
        keys = [keys setByAddingObject:NSStringFromSelector(@selector(jsonFileUrl))];
    }

    return keys;
}

- (instancetype)initWithTargetReport:(Report *)report
{
    self = [super init];
    if (!self) {
        return nil;
    }

    if (report == nil) {
        [NSException raise:@"IllegalArgumentException" format:@"targetReport is nil"];
    }

    _targetReport = report;

    return self;
}

- (BOOL)isReady
{
    return self.jsonFileUrl != nil && super.ready;
}

- (void)setJsonFileUrl:(NSURL *)jsonFileUrl
{
    if (self.executing) {
        [NSException raise:@"IllegalStateException" format:@"cannot change jsonFileUrl after ParseReportMetaDataOperation has started"];
    }

    _jsonFileUrl = jsonFileUrl;
}

@end
