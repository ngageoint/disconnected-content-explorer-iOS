//
//  ReportMetaData.m
//  DICE
//
//  Created by Robert St. John on 8/5/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "ParseJsonOperation.h"

// TODO: use NSFileManager or NSURLConnection/Session to load the json data for better testability
@implementation ParseJsonOperation

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSSet *keys = [super keyPathsForValuesAffectingValueForKey:key];

    NSString *readyKey = NSStringFromSelector(@selector(isReady));
    if ([readyKey isEqualToString:key]) {
        keys = [keys setByAddingObjectsFromArray:@[NSStringFromSelector(@selector(jsonUrl))]];
    }

    return keys;
}

+ (BOOL)automaticallyNotifiesObserversOfJsonUrl
{
    return NO;
}

- (instancetype)init
{
    return [self initWithFileManager:[NSFileManager defaultManager]];
}

- (instancetype)initWithFileManager:(NSFileManager *)fileManager
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _fileManager = fileManager;

    return self;
}

- (BOOL)isReady
{
    return (self.jsonUrl != nil || self.isCancelled) && super.isReady;
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

    [self willChangeValueForKey:jsonUrlKey];

    _jsonUrl = jsonUrl;

    [self didChangeValueForKey:jsonUrlKey];
}

- (void)main
{
    @autoreleasepool {
        NSData *jsonData = [self.fileManager contentsAtPath:self.jsonUrl.path];
        if (jsonData == nil) {
            return;
        }
        _parsedJsonDictionary = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
    }
}

@end
