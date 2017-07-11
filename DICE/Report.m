//
//  Report.m
//  InteractiveReports
//

#import "Report.h"


@implementation Report

@synthesize cacheFiles = _cacheFiles;

- (NSManagedObject *)initWithEntity:(NSEntityDescription *)entity insertIntoManagedObjectContext:(NSManagedObjectContext *)context
{
    self = [super initWithEntity:entity insertIntoManagedObjectContext:context];

    _cacheFiles = [NSMutableArray array];

    return self;
}

- (NSUInteger)downloadPercent
{
    return (NSUInteger)((double)self.downloadProgress / (double)self.downloadSize);
}

- (BOOL)isImportFinished
{
    ReportImportStatus status = self.importStatus;
    return status == ReportImportStatusSuccess || status == ReportImportStatusFailed;
}

- (NSURL *)thumbnail
{
    if (self.baseDir == nil || self.thumbnailPath == nil) {
        return nil;
    }
    return [self.baseDir URLByAppendingPathComponent:self.thumbnailPath isDirectory:NO];
}

- (NSURL *)tileThumbnail
{
    if (self.baseDir == nil || self.tileThumbnailPath == nil) {
        return nil;
    }
    return [self.baseDir URLByAppendingPathComponent:self.tileThumbnailPath isDirectory:NO];
}

- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor
{
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
            self.thumbnailPath = obj;
        }
        if ([@"tile_thumbnail" isEqualToString:key]) {
            self.tileThumbnailPath = obj;
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
