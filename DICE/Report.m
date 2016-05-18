//
//  Report.m
//  InteractiveReports
//

#import "Report.h"

@implementation Report

- (id) initWithTitle:(NSString *)title {
    self = [super init];

    if (self) {
        self.title = title;
        self.summary = nil;
        self.thumbnail = nil;
        self.fileExtension = nil;
        self.reportID = nil;
        self.isEnabled = NO;
        self.error = nil;
        self.totalNumberOfFiles = 0;
        self.progress = 0;
        self.downloadSize = 0;
        self.cacheFiles = [[NSMutableArray alloc] init];
        self.downloadProgress = 0;
    }
    
    return self;
}


- (NSURL *)thumbnailURL
{
    return [NSURL URLWithString:self.thumbnail];
}


- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor
{
    [descriptor enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([[NSNull null] isEqual:obj]) {
            return;
        }

        if ([@"reportID" isEqualToString:key]) {
            self.reportID = obj;
        }
        if ([@"title" isEqualToString:key]) {
            self.title = obj;
        }
        if ([@"description" isEqualToString:key]) {
            self.summary = obj;
        }
        if ([@"lat" isEqualToString:key]) {
            self.lat = obj;
        }
        if ([@"lon" isEqualToString:key]) {
            self.lon = obj;
        }
        if ([@"thumbnail" isEqualToString:key]) {
            self.thumbnail = obj;
        }
        if ([@"tile_thumbnail" isEqualToString:key]) {
            self.tileThumbnail = obj;
        }
    }];

    return self;
}

@end
