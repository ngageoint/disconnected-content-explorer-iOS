//
//  Report.m
//  InteractiveReports
//

#import "Report.h"

@implementation Report

- (id) init {
    self = [super init];

    if (self) {
        self.title = nil;
        self.summary = nil;
        self.thumbnail = nil;
        self.uti = NULL;
        self.reportID = nil;
        self.isEnabled = NO;
        self.downloadSize = 0;
        self.downloadProgress = 0;
        self.cacheFiles = [NSMutableArray array];
        self.importStatus = ReportImportStatusNewLocal;
    }
    
    return self;
}


- (NSURL *)thumbnailURL
{
    return [NSURL URLWithString:self.thumbnail];
}

- (BOOL)isImportFinished
{
    return self.importStatus == ReportImportStatusSuccess || self.importStatus == ReportImportStatusFailed;
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

- (NSString *)description
{
    return [NSString stringWithFormat:@"Report: %@ (%@)", self.title, self.sourceFile];
}

@end
