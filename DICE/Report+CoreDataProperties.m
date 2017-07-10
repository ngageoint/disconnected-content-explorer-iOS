//
//  Report+CoreDataProperties.m
//  DICE
//
//  Created by Robert St. John on 7/7/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "Report+CoreDataProperties.h"
#import "DICEConstants.h"

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
@dynamic thumbnailPath;
@dynamic tileThumbnailPath;
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

- (BOOL)validateForInsert:(NSError * _Nullable __autoreleasing *)error
{
    if (![super validateForInsert:error]) {
        return NO;
    }
    return [self validateForSave:error];
}

- (BOOL)validateForUpdate:(NSError * _Nullable __autoreleasing *)error
{
    if (![super validateForInsert:error]) {
        return NO;
    }
    return [self validateForSave:error];
}

- (BOOL)validateForSave:(NSError * _Nullable __autoreleasing *)error
{
    if (self.remoteSource == nil && self.sourceFile == nil) {
        NSDictionary *info = @{
            NSLocalizedDescriptionKey: @"validation: record must have a remote or local source URL"
        };
        *error = [NSError errorWithDomain:DICEPersistenceErrorDomain code:DICEInvalidSourceUrlErrorCode userInfo:info];
        return NO;
    }

    if (self.baseDir && self.importDir == nil) {
        NSDictionary *info = @{
            NSLocalizedDescriptionKey: @"validation: record has base dir, but no import dir"
        };
        *error = [NSError errorWithDomain:DICEPersistenceErrorDomain code:DICEInvalidImportDirErrorCode userInfo:info];
        return NO;
    }
    else if (self.baseDir && self.importDir) {
        NSString *baseDirParent = self.baseDir.path.stringByStandardizingPath.stringByDeletingLastPathComponent;
        NSString *importDir = self.importDir.path.stringByStandardizingPath;
        if (![baseDirParent isEqualToString:importDir]) {
            NSDictionary *info = @{
                NSLocalizedDescriptionKey: @"validation: base dir is not a child of import dir"
            };
            *error = [NSError errorWithDomain:DICEPersistenceErrorDomain code:DICEInvalidBaseDirErrorCode userInfo:info];
            return NO;
        }
    }

    if (self.rootFile && self.baseDir == nil) {
        NSDictionary *info = @{
            NSLocalizedDescriptionKey: @"validation: record has root file, but no base dir"
        };
        *error = [NSError errorWithDomain:DICEPersistenceErrorDomain code:DICEInvalidBaseDirErrorCode userInfo:info];
        return NO;
    }
    else if (self.rootFile) {
        
    }

    *error = nil;
    return YES;
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

@end
