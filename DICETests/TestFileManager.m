//
//  TestFileManager.m
//  DICE
//
//  Created by Robert St. John on 5/13/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "TestFileManager.h"
#import "NSString+PathUtils.h"


@interface TestFileManager_Node : NSObject <NSCopying>

@property (class, readonly, nonnull) NSComparator comparator;

@property (nullable) TestFileManager_Node *parent;
@property (readonly, nullable) NSMutableDictionary<NSString *, TestFileManager_Node *> *children;
@property (readonly, nonnull) NSString *name;
@property (readonly, nonnull) NSDictionary *attrs;
@property (readonly, nullable) NSMutableData *contents;
@property (readonly, nonnull) NSString *path;
@property (readonly) BOOL isDir;
@property (readonly) BOOL isFile;
@property (readonly, nonnull) NSComparator comparator;

- (nullable instancetype)initFileWithName:(nonnull NSString *)name attrs:(NSDictionary *)attrs;
- (nullable instancetype)initDirWithName:(nonnull NSString *)name attrs:(NSDictionary *)attrs;

/**
 * Returns self.
 */
- (nonnull instancetype)addChild:(nonnull TestFileManager_Node *)child;
/**
 * Returns self.
 */
- (nonnull instancetype)removeChild:(nonnull TestFileManager_Node *)child;
/**
 * Change self's name, updating the parent's child index.
 */
- (nonnull instancetype)changeName:(NSString *)name;
/**
 * Returns self.
 */
- (nonnull instancetype)moveToParent:(nullable TestFileManager_Node *)parent;
/**
 * Copy self to a new node, copying the contents and attributes, but not the children.
 */
- (nonnull instancetype)copyWithName:(nonnull NSString *)name;
/**
 * Return the named child or nil if self has no such child.
 */
- (nonnull instancetype)childWithName:(nonnull NSString *)name;
/**
 * Compare self to the given node.  Files always precede directories, then ordered by name.
 */
- (NSComparisonResult)compare:(TestFileManager_Node *)other;

@end


@implementation TestFileManager_Node
{
    NSMutableData *_contents;
}

static NSComparator _comparator = ^NSComparisonResult(TestFileManager_Node *left, TestFileManager_Node *right) {
    if (left.isFile != right.isFile) {
        return left.isFile ? NSOrderedAscending : NSOrderedDescending;
    }
    return [left.name compare:right.name];
};

+ (NSComparator)comparator
{
    return _comparator;
}

- (instancetype)initFileWithName:(NSString *)name attrs:(NSDictionary *)attrs
{
    self = [super init];
    _name = name;
    _contents = [NSMutableData data];
    NSMutableDictionary *mattrs = [attrs mutableCopy];
    [mattrs setObject:NSFileTypeRegular forKey:NSFileType];
    _attrs = [NSDictionary dictionaryWithDictionary:mattrs];
    _children = nil;
    return self;
}

- (instancetype)initDirWithName:(NSString *)name attrs:(NSDictionary *)attrs
{
    self = [super init];
    _name = name;
    _contents = nil;
    NSMutableDictionary *mattrs = [attrs mutableCopy];
    [mattrs setObject:NSFileTypeDirectory forKey:NSFileType];
    _attrs = [NSDictionary dictionaryWithDictionary:mattrs];
    _children = [NSMutableDictionary dictionary];
    return self;
}


- (instancetype)copyWithName:(NSString *)name
{
    TestFileManager_Node *copy;
    if (self.isFile) {
        copy = [[TestFileManager_Node alloc] initFileWithName:name attrs:self.attrs];
        [copy.contents setData:self.contents];
    }
    else {
        copy = [[TestFileManager_Node alloc] initDirWithName:name attrs:self.attrs];
    }
    return copy;
}

- (NSString *)path
{
    NSMutableString *path = self.name.mutableCopy;
    TestFileManager_Node *parent = self.parent;
    while (parent != nil) {
        [path insertString:@"/" atIndex:0];
        [path insertString:parent.name atIndex:0];
        parent = parent.parent;
    }
    return [@"/" stringByAppendingString:path];
}

- (instancetype)addChild:(TestFileManager_Node *)child
{
    _children[child.name] = child;
    child.parent = self;
    return self;
}

- (instancetype)removeChild:(TestFileManager_Node *)child
{
    [_children removeObjectForKey:child.name];
    child.parent = nil;
    return self;
}

- (instancetype)moveToParent:(TestFileManager_Node *)parent
{
    if (self.parent == parent) {
        return self;
    }
    [self.parent removeChild:self];
    [parent addChild:self];
    return self;
}

- (instancetype)changeName:(NSString *)name
{
    if ([self.name isEqualToString:name]) {
        return self;
    }
    TestFileManager_Node *parent = [self.parent removeChild:self];
    _name = name;
    [parent addChild:self];
    return self;
}

- (instancetype)childWithName:(NSString *)name
{
    if (self.isFile) {
        return nil;
    }
    return self.children[name];
}

- (BOOL)isFile
{
    return _children == nil;
}

- (BOOL)isDir
{
    return _children != nil;
}

- (NSUInteger)hash
{
    return [_name hash];
}

- (BOOL)isEqual:(id)object
{
    if (object == nil) {
        return NO;
    }
    if (![object isKindOfClass:[TestFileManager_Node class]]) {
        return NO;
    }
    TestFileManager_Node *other = (TestFileManager_Node *)object;
    return [self.path isEqual:other.path];
}

- (NSComparisonResult)compare:(TestFileManager_Node *)other
{
    return _comparator(self, other);
}

# pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    return [self copyWithName:self.name];
}

@end


@interface NSMutableArray<ObjectType> (Queue)

@property (readonly) ObjectType head;

- (void)enqueue:(ObjectType)item;
- (ObjectType)dequeue;

@end


@implementation NSMutableArray (Queue)

- (void)enqueue:(id)item
{
    [self insertObject:item atIndex:0];
}

- (id)dequeue
{
    id last = self.lastObject;
    [self removeLastObject];
    return last;
}

- (id)head
{
    return self.lastObject;
}

@end



@interface NSMutableArray<ObjectType> (Stack)

@property (readonly) ObjectType peek;

- (void)push:(ObjectType)item;
- (ObjectType)pop;
- (ObjectType)peek;

@end


@implementation NSMutableArray (Stack)

- (void)push:(id)item
{
    [self addObject:item];
}

- (id)pop
{
    return [self dequeue];
}

- (id)peek
{
    return self.head;
}

@end


@interface TestFileManager_DirectoryEnumerator : NSDirectoryEnumerator

- (instancetype)initWithRootNode:(TestFileManager_Node *)root;

@end


@implementation TestFileManager_DirectoryEnumerator {
    TestFileManager_Node *_root;
    TestFileManager_Node *_currentDir;
    NSArray<TestFileManager_Node *> *_currentDirChildren;
    NSMutableArray<TestFileManager_Node *> *_dirQueue;
    NSUInteger _cursor;
    BOOL _skipCurrentDirDescendants;
}

- (instancetype)initWithRootNode:(TestFileManager_Node *)root
{
    self = [super init];

    _currentDir = _root = root;
    _currentDirChildren = [_currentDir.children.allValues sortedArrayUsingSelector:@selector(compare:)];
    _dirQueue = [NSMutableArray array];
    _cursor = 0;
    _skipCurrentDirDescendants = NO;

    return self;
}

- (id)nextObject
{
    if (_cursor < _currentDirChildren.count) {
        TestFileManager_Node *next = _currentDirChildren[_cursor];
        if (next.isDir && !_skipCurrentDirDescendants) {
            [_dirQueue enqueue:next];
        }
        _cursor += 1;
        return [next.path pathRelativeToPath:_root.path];
    }

    _currentDir = [_dirQueue dequeue];
    if (_currentDir == nil) {
        return nil;
    }
    _currentDirChildren = [_currentDir.children.allValues sortedArrayUsingSelector:@selector(compare:)];
    _cursor = 0;
    _skipCurrentDirDescendants = NO;
    return [self nextObject];
}

- (NSArray *)allObjects
{
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    NSString *item;
    while ((item = [self nextObject])) {
        [all addObject:item];
    }
    return [NSArray arrayWithArray:all];
}

- (NSDictionary<NSFileAttributeKey,id> *)directoryAttributes
{
    return _root.attrs;
}

- (NSDictionary<NSFileAttributeKey,id> *)fileAttributes
{
    if (_cursor < _currentDirChildren.count) {
        return _currentDirChildren[_cursor - 1].attrs;
    }
    return nil;
}

- (void)skipDescendants
{
    _skipCurrentDirDescendants = YES;
    NSArray<TestFileManager_Node *> *possibleQueuedSubdirs = [_currentDirChildren subarrayWithRange:NSMakeRange(0, _cursor)];
    for (TestFileManager_Node *child in possibleQueuedSubdirs) {
        if (child.isDir) {
            [_dirQueue removeObject:child];
        }
    }
}

- (NSUInteger)level
{
    return _currentDir.path.pathComponents.count - _root.path.pathComponents.count;
}

@end


@implementation TestFileManager
{
    TestFileManager_Node *_root;
    NSString *_workingDir;
}

- (instancetype)init
{
    self = [super init];

    _root = [[TestFileManager_Node alloc] initDirWithName:@"" attrs:nil];

    return self;
}

- (NSString *)workingDir
{
    @synchronized (_root) {
        return _workingDir;
    }
}

- (void)setWorkingDir:(NSString *)workingDir
{
    @synchronized (_root) {
        _workingDir = workingDir.stringByStandardizingPath;
    }
}

- (NSString *)absolutify:(NSString *)absOrRelPath
{
    absOrRelPath = absOrRelPath.stringByStandardizingPath;
    if (absOrRelPath.isAbsolutePath) {
        return absOrRelPath;
    }
    return [self.workingDir stringByAppendingPathComponent:absOrRelPath];
}

- (TestFileManager_Node *)nodeAtPath:(NSString *)path
{
    @synchronized (_root) {
        path = [self absolutify:path];
        NSArray<NSString *> *names = path.pathComponents;
        // skip leading slash
        names = [names subarrayWithRange:NSMakeRange(1, names.count - 1)];
        TestFileManager_Node *cursor = _root;
        for (NSString *name in names) {
            cursor = [cursor childWithName:name];
            if (cursor == nil) {
                return nil;
            }
        }
        return cursor;
    }
}

- (instancetype)createPaths:(NSString *)relPath, ... NS_REQUIRES_NIL_TERMINATION
{
    @synchronized (_root) {
        va_list args;
        va_start(args, relPath);
        for(NSString *arg = relPath; arg != nil; arg = va_arg(args, NSString *)) {
            NSString *stdPath = [self absolutify:arg];
            NSString *parentPath = stdPath.stringByDeletingLastPathComponent;
            NSError *error;
            if (![self createDirectoryAtPath:parentPath withIntermediateDirectories:YES attributes:nil error:&error]) {
                [NSException raise:NSInvalidArgumentException format:@"error creating parent dir %@: %@", parentPath, error.localizedDescription];
            }
            if ([relPath hasSuffix:@"/"]) {
                if (![self createDirectoryAtPath:stdPath withIntermediateDirectories:YES attributes:nil error:&error]) {
                    [NSException raise:NSInvalidArgumentException format:@"error creating dir %@: %@", stdPath, error.localizedDescription];
                }
            }
            else if (![self createFileAtPath:stdPath contents:nil attributes:nil]) {
                [NSException raise:NSInvalidArgumentException format:@"error creating file %@", stdPath];
            }
        }
        va_end(args);
        return self;
    }
}

- (instancetype)createFilePath:(NSString *)path contents:(NSData *)data
{
    @synchronized (_root) {
        NSString *stdPath = [self absolutify:path];
        NSString *parentPath = stdPath.stringByDeletingLastPathComponent;
        NSError *error;
        if (![self createDirectoryAtPath:parentPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            [NSException raise:NSInvalidArgumentException format:@"error creating parent dir %@: %@", parentPath, error.localizedDescription];
        }
        if (![self createFileAtPath:stdPath contents:data attributes:nil]) {
            [NSException raise:NSInvalidArgumentException format:@"error creating file %@", stdPath];
        }
        return self;
    }
}

#pragma mark - NSFileManager overrides

- (BOOL)fileExistsAtPath:(NSString *)path
{
    @synchronized (_root) {
        return [self nodeAtPath:path] != nil;
    }
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory
{
    @synchronized (_root) {
        TestFileManager_Node *node = [self nodeAtPath:path];
        if (node) {
            *isDirectory = node.isDir;
            return YES;
        }
        *isDirectory = NO;
        return NO;
    }
}

- (NSArray *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray<NSString *> *)keys options:(NSDirectoryEnumerationOptions)mask error:(NSError **)error
{
    @synchronized (_root) {
        TestFileManager_Node *dirNode = [self nodeAtPath:url.path];
        if (!dirNode) {
            *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                userInfo:@{NSURLErrorKey: url, NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no file for url %@ exists", url]}];
        }
        if (dirNode.isFile) {
            *error = [[NSError alloc] initWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                 userInfo:@{NSURLErrorKey: url, NSLocalizedDescriptionKey: [NSString stringWithFormat:@"file at url %@ is not a directory", url]}];
        }
        NSMutableArray<NSURL *> *paths = [NSMutableArray array];
        for (TestFileManager_Node *child in dirNode.children.allValues) {
            [paths addObject:[NSURL fileURLWithPath:child.path isDirectory:child.isDir]];
        }
        return [NSArray arrayWithArray:paths];
    }
}

- (NSDirectoryEnumerator<NSString *> *)enumeratorAtPath:(NSString *)path
{
    @synchronized (_root) {
        TestFileManager_Node *pathNode = [self nodeAtPath:path];
        if (pathNode.isFile) {
            return nil;
        }
        return [[TestFileManager_DirectoryEnumerator alloc] initWithRootNode:pathNode];
    }
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary<NSString *, id> *)attr
{
    @synchronized (_root) {
        if (self.onCreateFileAtPath) {
            if (!self.onCreateFileAtPath(path)) {
                return NO;
            }
        }
        path = [self absolutify:path];
        TestFileManager_Node *parentDirNode = [self nodeAtPath:path.stringByDeletingLastPathComponent];
        if (parentDirNode == nil) {
            return NO;
        }
        else if (parentDirNode.isFile) {
            return NO;
        }
        TestFileManager_Node *node = [self nodeAtPath:path];
        if (node == nil) {
            node = [[[TestFileManager_Node alloc] initFileWithName:path.lastPathComponent attrs:attr] moveToParent:parentDirNode];
        }
        [node.contents setData:data];

        return YES;
    }
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSString *, id> *)attributes error:(NSError **)error
{
    @synchronized (_root) {
        if (self.onCreateDirectoryAtPath) {
            if (!self.onCreateDirectoryAtPath(path, createIntermediates, error)) {
                return NO;
            }
        }

        path = [self absolutify:path];
        NSString *baseName = path.lastPathComponent;
        NSString *parentPath = path.stringByDeletingLastPathComponent;
        TestFileManager_Node *node = [self nodeAtPath:parentPath];
        if (node) {
            if (node.isFile) {
                // TODO: set error
                return NO;
            }
            if ([node childWithName:baseName]) {
                return createIntermediates;
            }
            [[[TestFileManager_Node alloc] initDirWithName:baseName attrs:attributes] moveToParent:node];
            return YES;
        }
        else if (!createIntermediates) {
            // TODO: set error
            return NO;
        }

        node = _root;
        NSMutableArray<NSString *> *ancestorNames = [parentPath.pathComponents mutableCopy];
        while (ancestorNames.count) {
            NSString *ancestorName = ancestorNames.firstObject;
            [ancestorNames removeObjectAtIndex:0];
            TestFileManager_Node *child = [node childWithName:ancestorName];
            if (child) {
                node = child;
            }
            else {
                node = [[[TestFileManager_Node alloc] initDirWithName:ancestorName attrs:nil] moveToParent:node];
            }
        }

        [[[TestFileManager_Node alloc] initDirWithName:baseName attrs:attributes] moveToParent:node];

        return YES;
    }
}

- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSString *, id> *)attributes error:(NSError **)error
{
    return [self createDirectoryAtPath:url.path withIntermediateDirectories:createIntermediates attributes:attributes error:error];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError * _Nullable __autoreleasing *)error
{
    @synchronized (_root) {
        TestFileManager_Node *node = [self nodeAtPath:path];
        if (node == nil) {
            NSString *reason = [NSString stringWithFormat:@"the path %@ does not exist", path];
            if (error) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                    userInfo:@{NSLocalizedFailureReasonErrorKey: reason, NSLocalizedDescriptionKey: reason, NSFilePathErrorKey: path}];
            }
            return NO;
        }

        if (node.parent == nil) {
            // TODO: set error
            return NO;
        }

        [node.parent removeChild:node];

        return YES;
    }
}

- (BOOL)removeItemAtURL:(NSURL *)URL error:(NSError * _Nullable __autoreleasing *)error
{
    return [self removeItemAtPath:URL.path error:error];
}

- (NSData *)contentsAtPath:(NSString *)path
{
    TestFileManager_Node *node = [self nodeAtPath:path];
    if (node == nil) {
        return nil;
    }
    return node.contents;
}

- (NSDictionary<NSFileAttributeKey, id> *)attributesOfItemAtPath:(NSString *)path error:(NSError * _Nullable __autoreleasing *)error
{
    TestFileManager_Node *node = [self nodeAtPath:path];
    if (node == nil) {
        return nil;
    }
    return node.attrs;
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

    NSString *stdSourcePath = [self absolutify:srcPath];
    NSString *stdDestPath = [self absolutify:dstPath];

    @synchronized (_root) {
        TestFileManager_Node *sourceNode = [self nodeAtPath:stdSourcePath];
        if (sourceNode == nil) {
            if (error) {
                NSString *reason = [NSString stringWithFormat:@"the source path %@ does not exist", srcPath];
                *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:NSFileNoSuchFileError
                    userInfo:@{NSLocalizedFailureReasonErrorKey: reason, NSLocalizedDescriptionKey: reason, NSFilePathErrorKey: srcPath}];
            }
            return NO;
        }

        TestFileManager_Node *destNode = [self nodeAtPath:stdDestPath];
        if (destNode) {
            if (error) {
                NSString *reason = [NSString stringWithFormat:@"the destination path %@ already exists", dstPath];
                *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:NSFileWriteFileExistsError
                    userInfo:@{NSLocalizedFailureReasonErrorKey: reason, NSLocalizedDescriptionKey: reason, NSFilePathErrorKey: dstPath}];
            }
            return NO;
        }

        NSString *destParentPath = [stdDestPath stringByDeletingLastPathComponent];
        TestFileManager_Node *destParentNode = [self nodeAtPath:destParentPath];
        if (destParentNode == nil) {
            if (error) {
                NSString *reason = [NSString stringWithFormat:@"the parent of destination path %@ does not exist or is not a directory", dstPath];
                *error = [NSError errorWithDomain:NSStringFromClass([self class]) code:NSFileNoSuchFileError
                    userInfo:@{NSLocalizedFailureReasonErrorKey: reason, NSLocalizedDescriptionKey: reason, NSFilePathErrorKey: destParentPath}];
            }
            return NO;
        }

        NSString *destName = stdDestPath.lastPathComponent;
        [[[sourceNode moveToParent:nil] changeName:destName] moveToParent:destParentNode];

        return YES;
    }
}

- (BOOL)moveItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError * _Nullable __autoreleasing *)error
{
    return [self moveItemAtPath:srcURL.path toPath:dstURL.path error:error];
}

@end
