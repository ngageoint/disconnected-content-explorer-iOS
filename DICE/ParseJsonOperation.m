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

    NSString *readyKey = NSStringFromSelector(@selector(isReady));
    if ([readyKey isEqualToString:key]) {
        keys = [keys setByAddingObject:NSStringFromSelector(@selector(jsonUrl))];
    }

    return keys;
}

+ (BOOL)automaticallyNotifiesObserversOfJsonUrl
{
    return NO;
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

- (void)setJsonUrl:(NSURL *)jsonUrl
{
    if (self.executing) {
        [NSException raise:@"IllegalStateException" format:@"cannot change jsonFileUrl after ParseReportMetaDataOperation has started"];
    }

    if (self.jsonUrl == jsonUrl) {
        return;
    }

    NSString *jsonUrlKey = NSStringFromSelector(@selector(jsonUrl));
    NSString *isReadyKey = NSStringFromSelector(@selector(isReady));

    BOOL wasReady = self.isReady;

    [self willChangeValueForKey:jsonUrlKey];
    if (!wasReady && jsonUrl) {
        [self willChangeValueForKey:isReadyKey];
    }

    _jsonUrl = jsonUrl;

    [self didChangeValueForKey:jsonUrlKey];
    if (!wasReady && self.isReady) {
        [self didChangeValueForKey:isReadyKey];
    }
}

- (void)main
{
    @autoreleasepool {
        NSData *jsonData = [NSData dataWithContentsOfURL:self.jsonUrl];
        _parsedJsonDictionary = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    }
}

@end
