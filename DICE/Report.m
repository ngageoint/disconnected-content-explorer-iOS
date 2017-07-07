//
//  Report.m
//  InteractiveReports
//

#import "Report.h"


@implementation Report

@synthesize cacheFiles;

- (NSUInteger)downloadPercent
{
    return (NSUInteger)((double)self.downloadProgress / (double)self.downloadSize);
}

- (BOOL)isImportFinished
{
    ReportImportStatus status = self.importStatus;
    return status == ReportImportStatusSuccess || status == ReportImportStatusFailed;
}

- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor
{
    // TODO: core_data: use self.managedObjectContext?
    [descriptor enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([NSNull.null isEqual:obj]) {
            return;
        }

        if ([@"reportID" isEqualToString:key] || [@"contentId" isEqualToString:key]) {
            self.contentId = obj;
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
            self.thumbnailUrl = obj;
        }
        if ([@"tile_thumbnail" isEqualToString:key]) {
            self.tileThumbnailUrl = obj;
        }
    }];

    return self;
}

- (NSString *)description
{
    if (self.isFault) {
        return @"Report: Core Data Fault";
    }
    return [NSString stringWithFormat:@"Report: %@ (%@)", [self primitiveValueForKey:@"title"], [self primitiveValueForKey:@"sourceFile"]];
}

@end
