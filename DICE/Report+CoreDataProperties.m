//
//  Report+CoreDataProperties.m
//  DICE
//
//  Created by Robert St. John on 7/7/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "Report+CoreDataProperties.h"


static NSString * const kRemoteSource = @"remoteSource";
static NSString * const kRemoteSourcePersistent = @"remoteSourceUrl";
static NSString * const kSourceFile = @"sourceFile";
static NSString * const kSourceFilePersistent = @"sourceFileUrl";
static NSString * const kImportDir = @"importDir";
static NSString * const kImportDirPersistent = @"importDirUrl";
static NSString * const kBaseDir = @"baseDir";
static NSString * const kBaseDirPersistent = @"baseDirUrl";
static NSString * const kRootFile = @"rootFile";
static NSString * const kRootFilePersistent = @"rootFileUrl";
static NSString * const kThumbnail = @"thumbnail";
static NSString * const kThumbnailPersistent = @"thumbnailUrl";
static NSString * const kTileThumbnail = @"tileThumbnail";
static NSString * const kTileThumbnailPersistent = @"tileThumbnailUrl";

static NSDictionary * persistentAttrForTransientAttr;

@implementation Report (CoreDataProperties)

+ (void)initialize
{
    [super initialize];

    persistentAttrForTransientAttr = @{
        kRemoteSource: kRemoteSourcePersistent,
        kSourceFile: kSourceFilePersistent,
        kImportDir: kImportDirPersistent,
        kBaseDir: kBaseDirPersistent,
        kRootFile: kRootFilePersistent,
        kThumbnail: kThumbnailPersistent,
        kTileThumbnail: kTileThumbnailPersistent,
    };
}

+ (NSFetchRequest<Report *> *)fetchRequest {
	return [[NSFetchRequest alloc] initWithEntityName:@"Report"];
}

@dynamic baseDirUrl;
@dynamic contentId;
@dynamic downloadProgress;
@dynamic downloadSize;
@dynamic importDirUrl;
@dynamic importStatus;
@dynamic isEnabled;
@dynamic lat;
@dynamic lon;
@dynamic remoteSourceUrl;
@dynamic rootFileUrl;
@dynamic sourceFileUrl;
@dynamic statusMessage;
@dynamic summary;
@dynamic thumbnailUrl;
@dynamic tileThumbnailUrl;
@dynamic title;
@dynamic uti;

- (id)wrappedAccessValueForKey:(NSString *)key
{
    [self willAccessValueForKey:key];
    id x = [self primitiveValueForKey:key];
    [self didAccessValueForKey:key];
    return x;
}

- (void)setTransientValue:(id)value forKey:(NSString *)key persistentKey:(NSString *)persistentKey persistentValue:(id)persistentValue
{
    [self willChangeValueForKey:key];
    [self willChangeValueForKey:persistentKey];
    [self setPrimitiveValue:persistentValue forKey:persistentKey];
    [self setPrimitiveValue:value forKey:key];
    [self didChangeValueForKey:persistentKey];
    [self didChangeValueForKey:key];
}

- (void)awakeFromFetch
{
    [persistentAttrForTransientAttr.allValues enumerateObjectsUsingBlock:^(id  _Nonnull persistentKey, NSUInteger idx, BOOL * _Nonnull stop) {
        id persistentValue = [self primitiveValueForKey:persistentKey];
        [self setValue:persistentValue forKey:persistentKey];
    }];
}

- (void)setRemoteSourceUrl:(NSString *)remoteSourceUrl
{
    NSURL *x = [NSURL URLWithString:remoteSourceUrl];
    [self setTransientValue:x forKey:kRemoteSource persistentKey:kRemoteSourcePersistent persistentValue:remoteSourceUrl];
}

- (NSURL *)remoteSource
{
    return [self wrappedAccessValueForKey:kRemoteSource];
}

- (void)setRemoteSource:(NSURL *)remoteSource
{
    [self setTransientValue:remoteSource forKey:kRemoteSource persistentKey:kRemoteSourcePersistent persistentValue:remoteSource.absoluteString];
}

- (void)setSourceFileUrl:(NSString *)sourceFileUrl
{
    NSURL *transient = [NSURL URLWithString:sourceFileUrl];
    [self setTransientValue:transient forKey:kSourceFile persistentKey:kSourceFilePersistent persistentValue:sourceFileUrl];
}

- (NSURL *)sourceFile
{
    return [self wrappedAccessValueForKey:kSourceFile];
}

- (void)setSourceFile:(NSURL *)sourceFile
{
    [self setTransientValue:sourceFile forKey:kSourceFile persistentKey:kSourceFilePersistent persistentValue:sourceFile.absoluteString];
}

- (void)setImportDirUrl:(NSString *)importDirUrl
{
    NSURL *transient = [NSURL URLWithString:importDirUrl];
    [self setTransientValue:transient forKey:kImportDir persistentKey:kImportDirPersistent persistentValue:importDirUrl];
}

- (NSURL *)importDir
{
    return [self wrappedAccessValueForKey:kImportDir];
}

- (void)setImportDir:(NSURL *)importDir
{
    [self setTransientValue:importDir forKey:kImportDir persistentKey:kImportDirPersistent persistentValue:importDir.absoluteString];
}

- (void)setBaseDirUrl:(NSString *)baseDirUrl
{
    NSURL *transient = [NSURL URLWithString:baseDirUrl];
    [self setTransientValue:transient forKey:kBaseDir persistentKey:kBaseDirPersistent persistentValue:baseDirUrl];
}

- (NSURL *)baseDir
{
    return [self wrappedAccessValueForKey:kBaseDir];
}

- (void)setBaseDir:(NSURL *)baseDir
{
    [self setTransientValue:baseDir forKey:kBaseDir persistentKey:kBaseDirPersistent persistentValue:baseDir.absoluteString];
}

- (void)setRootFileUrl:(NSString *)rootFileUrl
{
    NSURL *transient = [NSURL URLWithString:rootFileUrl];
    [self setTransientValue:transient forKey:kRootFile persistentKey:kRootFilePersistent persistentValue:rootFileUrl];
}

- (NSURL *)rootFile
{
    return [self wrappedAccessValueForKey:kRootFile];
}

- (void)setRootFile:(NSURL *)rootFile
{
    [self setTransientValue:rootFile forKey:kRootFile persistentKey:kRootFilePersistent persistentValue:rootFile.absoluteString];
}

- (void)setThumbnailUrl:(NSString *)thumbnailUrl
{
    NSURL *transient = [NSURL URLWithString:thumbnailUrl];
    [self setTransientValue:transient forKey:kThumbnail persistentKey:kThumbnailPersistent persistentValue:thumbnailUrl];
}

- (NSURL *)thumbnail
{
    return [self wrappedAccessValueForKey:kThumbnail];
}

- (void)setThumbnail:(NSURL *)thumbnail
{
    [self setTransientValue:thumbnail forKey:kThumbnail persistentKey:kThumbnailPersistent persistentValue:thumbnail.absoluteString];
}

- (void)setTileThumbnailUrl:(NSString *)tileThumbnailUrl
{
    NSURL *transient = [NSURL URLWithString:tileThumbnailUrl];
    [self setTransientValue:transient forKey:kTileThumbnail persistentKey:kTileThumbnailPersistent persistentValue:tileThumbnailUrl];
}

- (NSURL *)tileThumbnail
{
    return [self wrappedAccessValueForKey:kTileThumbnail];
}

- (void)setTileThumbnail:(NSURL *)tileThumbnail
{
    [self setTransientValue:tileThumbnail forKey:kTileThumbnail persistentKey:kTileThumbnailPersistent persistentValue:tileThumbnail.absoluteString];
}

@end
