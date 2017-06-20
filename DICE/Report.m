//
//  Report.m
//  InteractiveReports
//

#import "Report.h"

@implementation Report

- (id) init {
    self = [super init];
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super init])) {
        return nil;
    }

    [self setPropertiesFromCoder:coder];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.baseDir forKey:NSStringFromSelector(@selector(baseDir))];
    [coder encodeObject:self.contentId forKey:NSStringFromSelector(@selector(contentId))];
    [coder encodeInteger:self.downloadProgress forKey:NSStringFromSelector(@selector(downloadProgress))];
    [coder encodeInteger:self.downloadSize forKey:NSStringFromSelector(@selector(downloadSize))];
    [coder encodeObject:self.importDir forKey:NSStringFromSelector(@selector(importDir))];
    [coder encodeInteger:self.importStatus forKey:NSStringFromSelector(@selector(importStatus))];
    [coder encodeBool:self.isEnabled forKey:NSStringFromSelector(@selector(isEnabled))];
    [coder encodeObject:self.lat forKey:NSStringFromSelector(@selector(lat))];
    [coder encodeObject:self.lon forKey:NSStringFromSelector(@selector(lon))];
    [coder encodeObject:self.remoteSource forKey:NSStringFromSelector(@selector(remoteSource))];
    [coder encodeObject:self.rootFile forKey:NSStringFromSelector(@selector(rootFile))];
    [coder encodeObject:self.sourceFile forKey:NSStringFromSelector(@selector(sourceFile))];
    [coder encodeObject:self.statusMessage forKey:NSStringFromSelector(@selector(statusMessage))];
    [coder encodeObject:self.summary forKey:NSStringFromSelector(@selector(summary))];
    [coder encodeObject:self.thumbnail forKey:NSStringFromSelector(@selector(thumbnail))];
    [coder encodeObject:self.tileThumbnail forKey:NSStringFromSelector(@selector(tileThumbnail))];
    [coder encodeObject:self.title forKey:NSStringFromSelector(@selector(title))];
    [coder encodeObject:self.uti forKey:NSStringFromSelector(@selector(uti))];
}

- (id)valueForKey:(NSString *)key
{
    if ([NSStringFromSelector(@selector(uti)) isEqualToString:key]) {
        return (NSString *)self.uti;
    }
    return [super valueForKey:key];
}

- (NSURL *)thumbnailURL
{
    return [NSURL URLWithString:self.thumbnail];
}

- (BOOL)isImportFinished
{
    ReportImportStatus status = self.importStatus;
    return status == ReportImportStatusSuccess || status == ReportImportStatusFailed;
}

- (instancetype)setPropertiesFromCoder:(NSCoder *)coder
{
    _baseDir = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(baseDir))];
    _contentId = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(contentId))];
    _downloadProgress = (NSUInteger) [coder decodeIntegerForKey:NSStringFromSelector(@selector(downloadProgress))];
    _downloadSize = (NSUInteger) [coder decodeIntegerForKey:NSStringFromSelector(@selector(downloadSize))];
    _importDir = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(importDir))];
    _importStatus = (ReportImportStatus) [coder decodeIntegerForKey:NSStringFromSelector(@selector(importStatus))];
    _isEnabled = [coder decodeBoolForKey:NSStringFromSelector(@selector(isEnabled))];
    _lat = [coder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(lat))];
    _lon = [coder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(lon))];
    _remoteSource = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(remoteSource))];
    _rootFile = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(rootFile))];
    _sourceFile = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(sourceFile))];
    _statusMessage = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(statusMessage))];
    _summary = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(summary))];
    _thumbnail = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(thumbnail))];
    _tileThumbnail = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(tileThumbnail))];
    _title = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(title))];
    _uti = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(uti))];

    return self;
}

- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor
{
    [descriptor enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([[NSNull null] isEqual:obj]) {
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
