//
//  TestFileManager.m
//  DICE
//
//  Created by Robert St. John on 5/13/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "TestFileManager.h"
#import "NSString+PathUtils.h"


@interface ReportStoreSpec_DirectoryEnumerator : NSDirectoryEnumerator

- (instancetype)initWithRootDir:(NSString *)rootDir descendants:(NSOrderedSet<NSString *> *)descendants fileManager:(NSFileManager *)fileManager;

@end


@implementation ReportStoreSpec_DirectoryEnumerator {
    NSString *_rootDir;
    NSOrderedSet<NSString *> *_descendants;
    NSFileManager *_fileManager;
    NSUInteger _cursor;
}

- (instancetype)initWithRootDir:(NSString *)rootDir descendants:(NSOrderedSet<NSString *> *)descendants fileManager:(NSFileManager *)fileManager
{
    self = [super init];

    _rootDir = rootDir;
    _descendants = descendants;
    _fileManager = fileManager;
    _cursor = 0;

    return self;
}

- (NSString *)lastReturnedPath
{
    if (_cursor == 0) {
        return nil;
    }
    NSString *relPath = [_descendants objectAtIndex:_cursor - 1];
    return [_rootDir stringByAppendingPathComponent:relPath];
}

- (id)nextObject
{
    if (_cursor == _descendants.count) {
        return nil;
    }
    NSString *current = [_descendants objectAtIndex:_cursor];
    _cursor += 1;
    return current;
}

- (NSDictionary<NSFileAttributeKey,id> *)directoryAttributes
{
    return [_fileManager attributesOfItemAtPath:_rootDir error:NULL];
}

- (NSDictionary<NSFileAttributeKey,id> *)fileAttributes
{
    NSString *absPath = self.lastReturnedPath;
    return [_fileManager attributesOfItemAtPath:absPath error:NULL];
}

- (void)skipDescendants
{

}

- (NSUInteger)level
{
    if (self.lastReturnedPath == nil) {
        return 0;
    }
    return self.lastReturnedPath.pathComponents.count - _rootDir.pathComponents.count - 1;
}

@end


@implementation TestFileManager

- (instancetype)init
{
    self = [super init];
    self.pathsInRootDir = [NSMutableOrderedSet orderedSet];
    self.pathAttrs = [NSMutableDictionary dictionary];
    self.contentsAtPath = [NSMutableDictionary dictionary];
    return self;
}

- (NSString *)pathRelativeToReportsDirOfPath:(NSString *)absolutePath
{
    return [absolutePath pathRelativeToPath:self.rootDir.path];
}

- (BOOL)fileExistsAtPath:(NSString *)path
{
    @synchronized (self) {
        NSString *relPath = [self pathRelativeToReportsDirOfPath:path];
        return relPath != nil && (relPath.length == 0 || [self.pathsInRootDir containsObject:relPath]);
    }
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory
{
    @synchronized (self) {
        if (![self fileExistsAtPath:path]) {
            *isDirectory = NO;
            return NO;
        }
        NSString *relPath = [self pathRelativeToReportsDirOfPath:path];
        *isDirectory = relPath.length == 0 || (self.pathAttrs[relPath] && [self.pathAttrs[relPath][NSFileType] isEqualToString:NSFileTypeDirectory]);
        return YES;
    }
}

- (NSArray *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray<NSString *> *)keys options:(NSDirectoryEnumerationOptions)mask error:(NSError **)error
{
    @synchronized (self) {
        NSMutableArray *paths = [NSMutableArray array];
        for (NSString *relPath in self.pathsInRootDir) {
            if (relPath.pathComponents.count == 1) {
                BOOL isDir = [NSFileTypeDirectory isEqualToString:self.pathAttrs[relPath][NSFileType]];
                NSURL *url = [self.rootDir URLByAppendingPathComponent:relPath isDirectory:isDir];
                [paths addObject:url];
            }
        }
        return paths;
    }
}

- (NSDirectoryEnumerator<NSString *> *)enumeratorAtPath:(NSString *)path
{
    @synchronized (self) {
        BOOL isDir;
        if (![self fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
            return nil;
        }
        NSOrderedSet<NSString *> *descendants = [self descendantRelativePathsOfDir:path];
        ReportStoreSpec_DirectoryEnumerator *enumerator = [[ReportStoreSpec_DirectoryEnumerator alloc] initWithRootDir:path descendants:descendants fileManager:self];
        return enumerator;
    }
}

- (NSOrderedSet<NSString *> *)descendantRelativePathsOfDir:(NSString *)rootDir
{
    @synchronized (self) {
        NSString *relRootDir = [self pathRelativeToReportsDirOfPath:rootDir];
        if (relRootDir == nil) {
            return nil;
        }
        NSUInteger pos = [self.pathsInRootDir indexOfObject:relRootDir];
        if (pos == self.pathsInRootDir.count - 1) {
            return [NSOrderedSet orderedSet];
        }
        pos += 1;
        relRootDir = [relRootDir stringByAppendingString:@"/"];
        NSMutableOrderedSet *descendants = [NSMutableOrderedSet orderedSetWithCapacity:self.pathsInRootDir.count - pos];
        while (pos < self.pathsInRootDir.count) {
            NSString *descendant = [self.pathsInRootDir objectAtIndex:pos];
            if ([descendant hasPrefix:relRootDir]) {
                descendant = [descendant pathRelativeToPath:relRootDir];
                [descendants addObject:descendant];
                pos += 1;
            }
            else {
                pos = self.pathsInRootDir.count;
            }
        }
        return descendants;
    }
}

- (void)setContentsOfRootDir:(NSString *)relPath, ...
{
    @synchronized (self) {
        [self.pathsInRootDir removeAllObjects];
        [self.pathAttrs removeAllObjects];
        if (relPath == nil) {
            return;
        }
        va_list args;
        va_start(args, relPath);
        for(NSString *arg = relPath; arg != nil; arg = va_arg(args, NSString *)) {
            [self addPath:arg attributes:nil];
        }
        va_end(args);
    }
}

- (instancetype)addPath:(NSString *)relPath attributes:(NSDictionary *)attrs
{
    @synchronized (self) {
        if (!attrs) {
            attrs = @{};
        }
        NSMutableDictionary *mutableAttrs = [NSMutableDictionary dictionaryWithDictionary:attrs];
        if ([relPath hasSuffix:@"/"]) {
            relPath = [relPath stringByReplacingCharactersInRange:NSMakeRange(relPath.length - 1, 1) withString:@""];
            if (!mutableAttrs[NSFileType]) {
                mutableAttrs[NSFileType] = NSFileTypeDirectory;
            }
        }
        else if (!mutableAttrs[NSFileType]) {
            mutableAttrs[NSFileType] = NSFileTypeRegular;
        }
        NSUInteger pos = [self.pathsInRootDir indexOfObject:relPath inSortedRange:NSMakeRange(0, self.pathsInRootDir.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(NSString * _Nonnull obj1, NSString * _Nonnull obj2) {
            return [obj1 localizedStandardCompare:obj2];
        }];
        [self.pathsInRootDir insertObject:relPath atIndex:pos];
        self.pathAttrs[relPath] = [NSDictionary dictionaryWithDictionary:mutableAttrs];
    }

    return self;
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary<NSString *, id> *)attr
{
    @synchronized (self) {
        if (self.onCreateFileAtPath) {
            if (!self.onCreateFileAtPath(path)) {
                return NO;
            }
        }
        BOOL isDir;
        if ([self fileExistsAtPath:path isDirectory:&isDir]) {
            return !isDir;
        }
        NSString *relPath = [self pathRelativeToReportsDirOfPath:path];
        if (relPath == nil) {
            return NO;
        }
        [self addPath:relPath attributes:attr];
        return YES;
    }
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSString *, id> *)attributes error:(NSError **)error
{
    return [self createDirectoryAtURL:[NSURL fileURLWithPath:path isDirectory:YES] withIntermediateDirectories:createIntermediates attributes:attributes error:error];
}

- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSString *, id> *)attributes error:(NSError **)error
{
    @synchronized (self) {
        if (self.onCreateDirectoryAtURL) {
            if (!self.onCreateDirectoryAtURL(url, createIntermediates, error)) {
                return NO;
            }
        }
        BOOL isDir;
        if ([self fileExistsAtPath:url.path isDirectory:&isDir]) {
            return isDir && createIntermediates;
        }
        NSString *relPath = [self pathRelativeToReportsDirOfPath:url.path];
        NSMutableArray<NSString *> *relPathParts = [relPath.pathComponents mutableCopy];
        relPath = @"";
        while (relPathParts.count > 0) {
            NSString *part = relPathParts.firstObject;
            [relPathParts removeObjectAtIndex:0];
            relPath = [relPath stringByAppendingPathComponent:part];
            NSString *absPath = [self.rootDir.path stringByAppendingPathComponent:relPath];
            BOOL isDir;
            if ([self fileExistsAtPath:absPath isDirectory:&isDir]) {
                if (!isDir) {
                    if (error) {
                        NSString *reason = [NSString stringWithFormat:@"non-directory already exists at path %@", absPath];
                        *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedFailureReasonErrorKey: reason}];
                    }
                    return NO;
                }
            }
            else if (createIntermediates) {
                [self addPath:relPath attributes:@{NSFileType: NSFileTypeDirectory}];
            }
            else {
                if (error) {
                    NSString *reason = [NSString stringWithFormat:@"intermediate directory %@ does not exist path", absPath];
                    *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedFailureReasonErrorKey: reason}];
                }
                return NO;
            }
        }
        return YES;
    }
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError * _Nullable __autoreleasing *)error
{
    @synchronized (self) {
        BOOL isDir;
        if (![self fileExistsAtPath:path isDirectory:&isDir]) {
            NSString *reason = [NSString stringWithFormat:@"the path %@ does not exist", path];
            if (error) {
                *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedFailureReasonErrorKey: reason, NSLocalizedDescriptionKey: reason}];
            }
            return NO;
        }
        NSString *relativePath = [self pathRelativeToReportsDirOfPath:path];
        if (relativePath == nil) {
            return NO;
        }
        NSUInteger index = [self.pathsInRootDir indexOfObject:relativePath];
        if (index == NSNotFound) {
            return NO;
        }
        if (!isDir) {
            [self.pathsInRootDir removeObjectAtIndex:index];
            return YES;
        }

        NSOrderedSet *descendants = [self descendantRelativePathsOfDir:path];
        for (NSString *descendant in descendants) {
            NSString *descendantAbsPath = [path stringByAppendingPathComponent:descendant];
            NSString *descendantRelPath = [self pathRelativeToReportsDirOfPath:descendantAbsPath];
            [self.pathsInRootDir removeObject:descendantRelPath];
        }
        [self.pathsInRootDir removeObjectAtIndex:index];

        return YES;
    }
}

- (BOOL)removeItemAtURL:(NSURL *)URL error:(NSError * _Nullable __autoreleasing *)error
{
    return [self removeItemAtPath:URL.path error:error];
}

- (NSData *)contentsAtPath:(NSString *)path
{
    return self.contentsAtPath[path];
}

- (NSDictionary<NSFileAttributeKey, id> *)attributesOfItemAtPath:(NSString *)path error:(NSError * _Nullable __autoreleasing *)error
{
    NSString *relPath = [self pathRelativeToReportsDirOfPath:path];
    return self.pathAttrs[relPath];
}

- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError * _Nullable __autoreleasing *)error
{
    if (self.onMoveItemAtPath) {
        if (!self.onMoveItemAtPath(srcPath, dstPath, error)) {
            return NO;
        }
    }
    if ([srcPath isEqualToString:dstPath]) {
        return YES;
    }

    @synchronized (self) {
        BOOL isDir;
        if (![self fileExistsAtPath:srcPath isDirectory:&isDir]) {
            if (error != NULL) {
                NSString *reason = [NSString stringWithFormat:@"the source path %@ does not exist", srcPath];
                *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedFailureReasonErrorKey: reason}];
            }
            return NO;
        }

        if ([self fileExistsAtPath:dstPath]) {
            if (error != NULL) {
                NSString *reason = [NSString stringWithFormat:@"the destination path %@ already exists", dstPath];
                *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedFailureReasonErrorKey: reason}];
            }
            return NO;
        }

        NSString *destParent = [dstPath stringByDeletingLastPathComponent];
        BOOL destParentIsDir = NO;
        if (![self fileExistsAtPath:destParent isDirectory:&destParentIsDir] || !destParentIsDir) {
            if (error != NULL) {
                NSString *reason = [NSString stringWithFormat:@"the parent of destination path %@ does not exist or is not a directory", dstPath];
                *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:0 userInfo:@{NSLocalizedFailureReasonErrorKey: reason}];
            }
            return NO;
        }

        NSDictionary *srcAttrs = [self attributesOfItemAtPath:srcPath error:NULL];
        NSString *destRelPath = [self pathRelativeToReportsDirOfPath:dstPath];
        [self addPath:destRelPath attributes:srcAttrs];
        NSDirectoryEnumerator *descendants = [self enumeratorAtPath:srcPath];
        if (descendants) {
            NSString *srcRelPath = descendants.nextObject;
            while (srcRelPath != nil) {
                NSString *destRelPath = [dstPath stringByAppendingPathComponent:srcRelPath];
                destRelPath = [self pathRelativeToReportsDirOfPath:destRelPath];
                [self addPath:destRelPath attributes:descendants.fileAttributes];
                srcRelPath = descendants.nextObject;
            }
        }

        [self removeItemAtPath:srcPath error:error];

        return YES;
    }
}

- (BOOL)moveItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError * _Nullable __autoreleasing *)error
{
    return [self moveItemAtPath:srcURL.path toPath:dstURL.path error:error];
}

@end
