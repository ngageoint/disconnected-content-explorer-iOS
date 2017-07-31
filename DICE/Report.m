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
    return (NSUInteger)((double)self.downloadProgress / (double)self.downloadSize * 100.0);
}

- (BOOL)isImportFinished
{
    ReportImportStatus state = self.importState;
    ReportImportStatus stateToEnter = self.importStateToEnter;
    return state == stateToEnter && (state == ReportImportStatusSuccess || state == ReportImportStatusFailed);
}

- (NSURL *)baseDir
{
    if (self.importDir && self.baseDirName) {
        return [self.importDir URLByAppendingPathComponent:self.baseDirName isDirectory:YES];
    }
    return nil;
}

- (NSURL *)rootFile
{
    NSURL *baseDir = self.baseDir;
    if (baseDir && self.rootFilePath) {
        return [baseDir URLByAppendingPathComponent:self.rootFilePath];
    }
    return nil;
}

- (NSURL *)thumbnail
{
    if (self.baseDirName == nil || self.thumbnailPath == nil) {
        return nil;
    }
    return [self.baseDir URLByAppendingPathComponent:self.thumbnailPath isDirectory:NO];
}

- (NSURL *)tileThumbnail
{
    if (self.baseDirName == nil || self.tileThumbnailPath == nil) {
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

        if ([@"contentId" isEqualToString:key] || [@"content_id" isEqualToString:key] || [@"reportID" isEqualToString:key]) {
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
        if ([@"tileThumbnail" isEqualToString:key] || [@"tile_thumbnail" isEqualToString:key]) {
            self.tileThumbnailPath = obj;
        }
    }];

    return self;
}

@end
