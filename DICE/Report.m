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
        self.contentId = nil;
        self.isEnabled = NO;
        self.downloadSize = 0;
        self.downloadProgress = 0;
        self.cacheFiles = [NSMutableArray array];
        self.importStatus = ReportImportStatusNewLocal;
    }
    
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super init])) {
        return nil;
    }

    self.baseDir = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(baseDir))];
    self.contentId = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(contentId))];
    self.downloadProgress = (NSUInteger) [coder decodeIntegerForKey:NSStringFromSelector(@selector(downloadProgress))];
    self.downloadSize = (NSUInteger) [coder decodeIntegerForKey:NSStringFromSelector(@selector(downloadSize))];
    self.importDir = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(importDir))];
    self.importStatus = (ReportImportStatus) [coder decodeIntegerForKey:NSStringFromSelector(@selector(importStatus))];
    self.isEnabled = [coder decodeBoolForKey:NSStringFromSelector(@selector(isEnabled))];
    self.lat = [coder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(lat))];
    self.lon = [coder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(lon))];
    self.remoteSource = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(remoteSource))];
    self.rootFile = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(rootFile))];
    self.sourceFile = [coder decodeObjectOfClass:[NSURL class] forKey:NSStringFromSelector(@selector(sourceFile))];
    self.statusMessage = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(statusMessage))];
    self.summary = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(summary))];
    self.thumbnail = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(thumbnail))];
    self.tileThumbnail = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(tileThumbnail))];
    self.title = [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(title))];
    self.uti = (__bridge CFStringRef) [coder decodeObjectOfClass:[NSString class] forKey:NSStringFromSelector(@selector(uti))];

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
    [coder encodeObject:(NSString *)self.uti forKey:NSStringFromSelector(@selector(uti))];
}

- (id)valueForKey:(NSString *)key
{
    if ([NSStringFromSelector(@selector(uti)) isEqualToString:key]) {
        return (NSString *)self.uti;
    }
    return [super valueForKey:key];
}

- (void)setValue:(nullable id)value forKey:(NSString *)key
{
    if ([NSStringFromSelector(@selector(uti)) isEqualToString:key]) {
        NSString *utiStr = (NSString *)value;
        self.uti = (__bridge CFStringRef)utiStr;
    }
    else {
        [super setValue:value forKey:key];
    }
}

- (void)setNilValueForKey:(NSString *)key
{
    if ([NSStringFromSelector(@selector(uti)) isEqualToString:key]) {
        self.uti = NULL;
    }
    else {
        [super setNilValueForKey:key];
    }
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
