#import "Report.h"
#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <JGMethodSwizzler/JGMethodSwizzler.h>

#import "DICEArchive.h"
#import "DICEExtractReportOperation.h"
#import "FileOperations.h"
#import "ImportProcess+Internal.h"
#import "NotificationRecordingObserver.h"
#import "NSOperation+Blockable.h"
#import "NSString+PathUtils.h"
#import "ReportStore.h"
#import "ReportType.h"
#import "TestDICEArchive.h"
#import "TestOperationQueue.h"
#import "TestReportType.h"
#import "DICEUtiExpert.h"
#import "DICEDownloadManager.h"


@class ReportStoreSpec_FileManager;


@interface ReportStoreSpec_DirectoryEnumerator : NSDirectoryEnumerator

- (instancetype)initWithRootDir:(NSString *)rootDir descendants:(NSOrderedSet<NSString *> *)descendants fileManager:(NSFileManager *)fileManager;

@end



@interface ReportStoreSpec_FileManager : NSFileManager

@property NSURL *reportsDir;
@property NSMutableOrderedSet<NSString *> *pathsInReportsDir;
@property NSMutableDictionary *pathAttrs;
@property BOOL (^onCreateFileAtPath)(NSString *path);
@property BOOL (^onCreateDirectoryAtURL)(NSURL *path, BOOL createIntermediates, NSError **error);
@property NSMutableDictionary<NSString *, NSData *> *contentsAtPath;

- (void)setContentsOfReportsDir:(NSString *)relPath, ... NS_REQUIRES_NIL_TERMINATION;

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


@implementation ReportStoreSpec_FileManager

- (instancetype)init
{
    self = [super init];
    self.pathsInReportsDir = [NSMutableOrderedSet orderedSet];
    self.pathAttrs = [NSMutableDictionary dictionary];
    self.contentsAtPath = [NSMutableDictionary dictionary];
    return self;
}

- (NSString *)pathRelativeToReportsDirOfPath:(NSString *)absolutePath
{
    return [absolutePath pathRelativeToPath:self.reportsDir.path];
}

- (BOOL)fileExistsAtPath:(NSString *)path
{
    @synchronized (self) {
        NSString *relPath = [self pathRelativeToReportsDirOfPath:path];
        return relPath != nil && (relPath.length == 0 || [self.pathsInReportsDir containsObject:relPath]);
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
        for (NSString *relPath in self.pathsInReportsDir) {
            if (relPath.pathComponents.count == 1) {
                BOOL isDir = [NSFileTypeDirectory isEqualToString:self.pathAttrs[relPath][NSFileType]];
                NSURL *url = [self.reportsDir URLByAppendingPathComponent:relPath isDirectory:isDir];
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
        NSUInteger pos = [self.pathsInReportsDir indexOfObject:relRootDir];
        if (pos == self.pathsInReportsDir.count - 1) {
            return [NSOrderedSet orderedSet];
        }
        pos += 1;
        relRootDir = [relRootDir stringByAppendingString:@"/"];
        NSMutableOrderedSet *descendants = [NSMutableOrderedSet orderedSetWithCapacity:self.pathsInReportsDir.count - pos];
        while (pos < self.pathsInReportsDir.count) {
            NSString *descendant = [self.pathsInReportsDir objectAtIndex:pos];
            if ([descendant hasPrefix:relRootDir]) {
                descendant = [descendant pathRelativeToPath:relRootDir];
                [descendants addObject:descendant];
                pos += 1;
            }
            else {
                pos = self.pathsInReportsDir.count;
            }
        }
        return descendants;
    }
}

- (void)setContentsOfReportsDir:(NSString *)relPath, ...
{
    @synchronized (self) {
        [self.pathsInReportsDir removeAllObjects];
        [self.pathAttrs removeAllObjects];
        if (relPath == nil) {
            return;
        }
        va_list args;
        va_start(args, relPath);
        for(NSString *arg = relPath; arg != nil; arg = va_arg(args, NSString *)) {
            [self addPathInReportsDir:arg withAttributes:nil];
        }
        va_end(args);
    }
}

- (void)addPathInReportsDir:(NSString *)relPath withAttributes:(NSDictionary *)attrs
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
        NSUInteger pos = [self.pathsInReportsDir indexOfObject:relPath inSortedRange:NSMakeRange(0, self.pathsInReportsDir.count) options:NSBinarySearchingInsertionIndex usingComparator:^NSComparisonResult(NSString * _Nonnull obj1, NSString * _Nonnull obj2) {
            return [obj1 localizedStandardCompare:obj2];
        }];
        [self.pathsInReportsDir insertObject:relPath atIndex:pos];
        self.pathAttrs[relPath] = [NSDictionary dictionaryWithDictionary:mutableAttrs];
    }
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
        [self addPathInReportsDir:relPath withAttributes:attr];
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
            NSString *absPath = [self.reportsDir.path stringByAppendingPathComponent:relPath];
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
                [self addPathInReportsDir:relPath withAttributes:@{NSFileType: NSFileTypeDirectory}];
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
        NSUInteger index = [self.pathsInReportsDir indexOfObject:relativePath];
        if (index == NSNotFound) {
            return NO;
        }
        if (!isDir) {
            [self.pathsInReportsDir removeObjectAtIndex:index];
            return YES;
        }

        NSOrderedSet *descendants = [self descendantRelativePathsOfDir:path];
        for (NSString *descendant in descendants) {
            NSString *descendantAbsPath = [path stringByAppendingPathComponent:descendant];
            NSString *descendantRelPath = [self pathRelativeToReportsDirOfPath:descendantAbsPath];
            [self.pathsInReportsDir removeObject:descendantRelPath];
        }
        [self.pathsInReportsDir removeObjectAtIndex:index];

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
        [self addPathInReportsDir:destRelPath withAttributes:srcAttrs];
        NSDirectoryEnumerator *descendants = [self enumeratorAtPath:srcPath];
        if (descendants) {
            NSString *srcRelPath = descendants.nextObject;
            while (srcRelPath != nil) {
                NSString *destRelPath = [dstPath stringByAppendingPathComponent:srcRelPath];
                destRelPath = [self pathRelativeToReportsDirOfPath:destRelPath];
                [self addPathInReportsDir:destRelPath withAttributes:descendants.fileAttributes];
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

/**
 This category enables the OCHamcrest endsWith matcher to accept
 NSURL objects.
 */
@interface NSURL (HasSuffixSupport)

- (BOOL)hasSuffix:(NSString *)suffix;

@end

@implementation NSURL (HasSuffixSupport)

- (BOOL)hasSuffix:(NSString *)suffix
{
    return [self.path hasSuffix:suffix];
}

@end


SpecBegin(ReportStore)

describe(@"ReportStore_FileManager", ^{

    __block ReportStoreSpec_FileManager *fileManager;
    __block NSURL *reportsDir;

    beforeEach(^{
        fileManager = [[ReportStoreSpec_FileManager alloc] init];
        fileManager.reportsDir = reportsDir = [NSURL fileURLWithPath:@"/dice" isDirectory:YES];
    });

    it(@"works", ^{
        [fileManager setContentsOfReportsDir:@"hello.txt", @"dir/", nil];

        BOOL isDir;
        BOOL *isDirOut = &isDir;

        expect([fileManager fileExistsAtPath:reportsDir.path isDirectory:isDirOut]).to.beTruthy();
        expect(isDir).to.beTruthy();

        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"hello.txt"].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(NO);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"dir" isDirectory:YES].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(YES);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"dir"].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(YES);

        expect(fileManager.pathsInReportsDir).to.contain(@"dir");
        expect([fileManager removeItemAtURL:[reportsDir URLByAppendingPathComponent:@"does_not_exist"] error:NULL]).to.equal(NO);
        expect([fileManager removeItemAtURL:[reportsDir URLByAppendingPathComponent:@"dir"] error:NULL]).to.equal(YES);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"dir"].path]).to.equal(NO);
        expect(fileManager.pathsInReportsDir).notTo.contain(@"dir");

        expect([fileManager createFileAtPath:[reportsDir URLByAppendingPathComponent:@"new.txt"].path contents:nil attributes:nil]).to.equal(YES);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"new.txt"].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(NO);
        NSUInteger pathCount = fileManager.pathsInReportsDir.count;
        expect([fileManager createFileAtPath:[reportsDir.path stringByAppendingPathComponent:@"new.txt"] contents:nil attributes:nil]).to.equal(YES);
        expect([fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"new.txt"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.equal(NO);
        expect(fileManager.pathsInReportsDir.count).to.equal(pathCount);

        expect([fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.equal(YES);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"dir"].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(YES);
        pathCount = fileManager.pathsInReportsDir.count;
        expect([fileManager createFileAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir"] contents:nil attributes:nil]).to.equal(NO);
        expect([fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.equal(YES);
        expect([fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:NO attributes:nil error:NULL]).to.equal(NO);
        expect(fileManager.pathsInReportsDir.count).to.equal(pathCount);

        NSString *intermediates = [reportsDir.path stringByAppendingPathComponent:@"dir1/dir2/dir3"];
        expect([fileManager createDirectoryAtPath:intermediates withIntermediateDirectories:NO attributes:nil error:NULL]).to.beFalsy();
        expect([fileManager fileExistsAtPath:intermediates]).to.beFalsy();
        expect([fileManager fileExistsAtPath:intermediates.stringByDeletingLastPathComponent]).to.beFalsy();
        expect([fileManager fileExistsAtPath:intermediates.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent]).to.beFalsy();
        expect([fileManager createDirectoryAtPath:intermediates withIntermediateDirectories:YES attributes:nil error:NULL]).to.beTruthy();
        expect([fileManager fileExistsAtPath:intermediates]).to.beTruthy();
        expect([fileManager fileExistsAtPath:intermediates.stringByDeletingLastPathComponent]).to.beTruthy();
        expect([fileManager fileExistsAtPath:intermediates.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent]).to.beTruthy();


        expect([fileManager createFileAtPath:@"/not/in/reportsDir.txt" contents:nil attributes:nil]).to.equal(NO);
        expect([fileManager fileExistsAtPath:@"/not/in/reportsDir.txt" isDirectory:isDirOut]).to.equal(NO);
        expect(isDir).to.equal(NO);

        describe(@"removing files", ^{

            beforeEach(^{
                [fileManager setContentsOfReportsDir:@"dir/", @"dir/file.txt", @"dir/dir/", @"dir/dir/file.txt", @"file.txt", nil];
            });

            it(@"removes a single file", ^{
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"file.txt"]]).to.beTruthy();
                expect([fileManager removeItemAtPath:[reportsDir.path stringByAppendingPathComponent:@"file.txt"] error:NULL]).to.beTruthy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"file.txt"]]).to.beFalsy();
            });

            it(@"removes a file from a subdirectory", ^{
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beTruthy();
                expect([fileManager removeItemAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/file.txt"] error:NULL]).to.beTruthy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beFalsy();
            });

            it(@"removes a directory and its descendants", ^{
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir"]]).to.beTruthy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beTruthy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/dir"]]).to.beTruthy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/dir/file.txt"]]).to.beTruthy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"file.txt"]]).to.beTruthy();

                expect([fileManager removeItemAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/"] error:NULL]).to.beTruthy();

                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/"]]).to.beFalsy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beFalsy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/dir"]]).to.beFalsy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir/dir/file.txt"]]).to.beFalsy();
                expect([fileManager fileExistsAtPath:[reportsDir.path stringByAppendingPathComponent:@"file.txt"]]).to.beFalsy();
            });

        });

        describe(@"moving files", ^{

            BOOL isDir;
            BOOL *isDirOut = &isDir;
            __block NSError *error;
            NSString *source = [reportsDir.path stringByAppendingPathComponent:@"move_src.txt"];
            NSString *dest = [reportsDir.path stringByAppendingPathComponent:@"move_dest.txt"];
            [fileManager createFileAtPath:source contents:nil attributes:nil];
            expect([fileManager moveItemAtPath:source toPath:dest error:&error]).to.beTruthy();
            expect([fileManager fileExistsAtPath:source isDirectory:isDirOut]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:dest isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect(error).to.beNil();

            source = [reportsDir.path stringByAppendingPathComponent:@"src_base"];
            dest = [reportsDir.path stringByAppendingPathComponent:@"dest_base"];
            [fileManager setContentsOfReportsDir:
                @"src_base/",
                @"src_base/child1.txt",
                @"src_base/child2/",
                @"src_base/child2/grand_child.txt",
                nil];
            expect([fileManager fileExistsAtPath:source isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"child1.txt"] isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"child2/"] isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"child2/grand_child.txt"] isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beFalsy();

            expect([fileManager moveItemAtPath:source toPath:dest error:&error]).to.beTruthy();

            expect([fileManager fileExistsAtPath:dest isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager fileExistsAtPath:[dest stringByAppendingPathComponent:@"child1.txt"] isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[dest stringByAppendingPathComponent:@"child2/"] isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager fileExistsAtPath:[dest stringByAppendingPathComponent:@"child2/grand_child.txt"] isDirectory:isDirOut]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:source isDirectory:isDirOut]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"chi1d1.txt"] isDirectory:isDirOut]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"chi1d2/"] isDirectory:isDirOut]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"chi1d2/grand_child.txt"] isDirectory:isDirOut]).to.beFalsy();
            expect(isDir).to.beFalsy();

        });

    });

});

describe(@"NSFileManager", ^{

    it(@"returns directory url with trailing slash", ^{
        NSURL *resources = [[[NSBundle bundleForClass:[self class]] bundleURL] URLByAppendingPathComponent:@"etc" isDirectory:YES];
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:resources includingPropertiesForKeys:nil options:0 error:NULL];
        NSURL *dirUrl;
        for (NSURL *url in contents) {
            if ([url.lastPathComponent isEqualToString:@"a_directory"]) {
                dirUrl = url;
            }
        }

        expect([dirUrl.absoluteString hasSuffix:@"/"]).to.equal(YES);
        expect([dirUrl.path hasSuffix:@"/"]).to.equal(NO);

        NSString *resourceType;
        [dirUrl getResourceValue:&resourceType forKey:NSURLFileResourceTypeKey error:NULL];
        expect(resourceType).to.equal(NSURLFileResourceTypeDirectory);
    });

});

describe(@"ReportStore", ^{

    __block TestReportType *redType;
    __block TestReportType *blueType;
    __block ReportStoreSpec_FileManager *fileManager;
    __block id<DICEArchiveFactory> archiveFactory;
    __block DICEDownloadManager *downloadManager;
    __block TestOperationQueue *importQueue;
    __block NSNotificationCenter *notifications;
    __block ReportStore *store;
    __block UIApplication *app;

    NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice/reports"];

    beforeAll(^{
    });

    beforeEach(^{
        fileManager = [[ReportStoreSpec_FileManager alloc] init];
        fileManager.reportsDir = reportsDir;
        archiveFactory = mockProtocol(@protocol(DICEArchiveFactory));
        downloadManager = mock([DICEDownloadManager class]);
        importQueue = [[TestOperationQueue alloc] init];
        notifications = [[NSNotificationCenter alloc] init];
        app = mock([UIApplication class]);

        redType = [[TestReportType alloc] initWithExtension:@"red" fileManager:fileManager];
        blueType = [[TestReportType alloc] initWithExtension:@"blue" fileManager:fileManager];

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir
            exclusions:nil
            utiExpert:[[DICEUtiExpert alloc] init]
            archiveFactory:archiveFactory
            importQueue:importQueue
            fileManager:fileManager
            notifications:notifications
            application:app];
        store.downloadManager = downloadManager;

        store.reportTypes = @[
            redType,
            blueType
        ];
    });

    afterEach(^{
        [importQueue waitUntilAllOperationsAreFinished];
        stopMocking(archiveFactory);
        stopMocking(app);
        fileManager = nil;
    });

    afterAll(^{
        
    });

    describe(@"loadReports", ^{

        beforeEach(^{
        });

        it(@"creates reports for each file in reports directory", ^{

            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", @"something.else", nil];

            id redImport = [redType enqueueImport];
            id blueImport = [blueType enqueueImport];

            NSArray *reports = [store loadReports];

            expect(reports.count).to.equal(3);
            expect(((Report *)reports[0]).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(((Report *)reports[2]).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"something.else"]);

            assertWithTimeout(1.0, thatEventually(@([redImport isFinished] && [blueImport isFinished])), isTrue());
        });

        it(@"removes reports with path that does not exist and are not importing", ^{
            
            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", nil];

            TestImportProcess *redImport = redType.enqueueImport;
            TestImportProcess *blueImport = blueType.enqueueImport;

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled && blueImport.report.isEnabled)), isTrue());

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            [fileManager setContentsOfReportsDir:@"report2.blue", nil];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports[0]).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

        it(@"leaves imported and importing reports in order of discovery", ^{

            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", @"report3.red", nil];

            TestImportProcess *blueImport = [blueType.enqueueImport block];
            TestImportProcess *redImport1 = [redType enqueueImport];
            TestImportProcess *redImport2 = [redType enqueueImport];

            NSArray<Report *> *reports1 = [NSArray arrayWithArray:[store loadReports]];

            expect(reports1.count).to.equal(3);
            expect(reports1[0].rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(reports1[1].rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(reports1[2].rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);

            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && redImport2.isFinished)), isTrue());

            [fileManager setContentsOfReportsDir:@"report2.blue", @"report3.red", @"report11.red", nil];
            redImport1 = [redType enqueueImport];

            NSArray<Report *> *reports2 = [NSArray arrayWithArray:[store loadReports]];

            expect(reports2.count).to.equal(3);
            expect(reports2[0].rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(reports2[0]).to.beIdenticalTo(reports1[1]);
            expect(reports2[1].rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);
            expect(reports2[1]).to.beIdenticalTo(reports1[2]);
            expect(reports2[2].rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report11.red"]);
            expect(reports2[2]).notTo.beIdenticalTo(reports1[0]);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && blueImport.report.isEnabled)), isTrue());
        });

        it(@"leaves reports whose path may not exist but are still importing", ^{

            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", nil];

            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSArray<Report *> *reports = [store loadReports];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(redImport.isFinished).to.equal(NO);
            expect([reports[0] isEnabled]).to.equal(NO);
            expect([reports[1] isEnabled]).to.equal(YES);

            Report *redReport = redImport.report;
            redReport.rootResource = [reportsDir URLByAppendingPathComponent:@"report1.transformed"];

            [fileManager setContentsOfReportsDir:@"report1.transformed", nil];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports.firstObject).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report1.transformed"]);
            expect(((Report *)reports.firstObject).isEnabled).to.equal(NO);

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            expect(store.reports.count).to.equal(1);
            expect(((Report *)store.reports.firstObject).rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"report1.transformed"]);
            expect(((Report *)store.reports.firstObject).isEnabled).to.equal(YES);
        });

        it(@"sends notifications about added reports", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil];

            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", nil];

            [redType.enqueueImport cancelAll];
            [blueType.enqueueImport cancelAll];

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(2));

            [observer.received enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSNotification *note = [obj notification];
                Report *report = note.userInfo[@"report"];

                expect(note.name).to.equal([ReportNotification reportAdded]);
                expect(report).to.beIdenticalTo(reports[idx]);
            }];

            [notifications removeObserver:observer];
        });

        it(@"posts a reports loaded notification", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportsLoaded on:notifications from:store withBlock:nil];
            [store loadReports];

            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(1));
        });

    });

    describe(@"attemptToImportReportFromResource", ^{

        it(@"imports a report with the capable ReportType", ^{

            TestImportProcess *redImport = redType.enqueueImport;

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());
        });

        it(@"posts a notification when the import begins", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportImportBegan on:notifications from:store withBlock:nil];

            [redType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(observer.received.count).to.equal(1);

            ReceivedNotification *received = observer.received.lastObject;
            NSNotification *note = received.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(received.wasMainThread).to.equal(YES);
            expect(report.importStatus).to.equal(ReportImportStatusSuccess);
        });

        it(@"posts a notification when the import finishes successfully", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];

            [redType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToUnsignedInteger(1));

            ReceivedNotification *received = observer.received.lastObject;
            NSNotification *note = received.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusSuccess);
            expect(received.wasMainThread).to.equal(YES);
        });

        it(@"posts a notification when the import finishes unsuccessfully", ^{
            
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];

            TestImportProcess *redImport = [redType enqueueImport];
            [redImport.steps.firstObject cancel];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToUnsignedInteger(1));

            ReceivedNotification *received = observer.received.lastObject;
            NSNotification *note = received.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
            expect(received.wasMainThread).to.equal(YES);
        });

        it(@"returns a report even if the url cannot be imported", ^{
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(report).notTo.beNil();
            expect(report.rootResource).to.equal(url);
        });

        it(@"assigns an error message if the report type was unknown", ^{
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusFailed));

            expect(report.summary).to.equal(@"Unknown content type");
        });

        it(@"adds the initial report to the report list", ^{
            TestImportProcess *import = [[redType enqueueImport] block];

            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            expect(store.reports).to.contain(report);
            expect(report.reportID).to.beNil();
            expect(report.title).to.equal(report.rootResource.lastPathComponent);
            expect(report.summary).to.equal(@"Importing content...");
            expect(report.isEnabled).to.equal(NO);
            
            [import unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
        });

        it(@"sends a notification about adding the report", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            [redType enqueueImport];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            [importQueue waitUntilAllOperationsAreFinished];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            ReceivedNotification *received = observer.received.firstObject;
            Report *receivedReport = received.notification.userInfo[@"report"];

            expect(received.notification.name).to.equal([ReportNotification reportAdded]);
            expect(receivedReport).to.beIdenticalTo(report);

            [notifications removeObserver:observer];
        });

        it(@"does not start an import for a report file it is already importing", ^{

            TestImportProcess *import = [redType.enqueueImport block];

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];
            Report *report = [store attemptToImportReportFromResource:reportUrl];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(report);
            expect(store.reports.firstObject).to.beIdenticalTo(notificationReport);
            expect(store.reports.count).to.equal(1);

            notificationReport = nil;
            [observer.received removeAllObjects];

            Report *sameReport = [store attemptToImportReportFromResource:reportUrl];

            [import unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(sameReport).to.beIdenticalTo(report);
            expect(store.reports.count).to.equal(1);
            expect(observer.received.count).to.equal(0);

            [notifications removeObserver:observer];
        });

        it(@"enables the report when the import finishes", ^{
            Report *report = mock([Report class]);
            TestImportProcess *import = [[TestImportProcess alloc] initWithReport:report];
            import.steps = @[[[NSOperation alloc] init]];
            [import.steps.firstObject start];

            __block BOOL enabledOnMainThread = NO;
            [givenVoid([report setIsEnabled:YES]) willDo:^id(NSInvocation *invocation) {
                BOOL enabled = NO;
                [invocation getArgument:&enabled atIndex:2];
                enabledOnMainThread = enabled && [NSThread isMainThread];
                return nil;
            }];

            [store importDidFinishForImportProcess:import];

            assertWithTimeout(1.0, thatEventually(@(enabledOnMainThread)), isTrue());
        });

        it(@"sends a notification when the import finishes", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportImportFinished] on:notifications from:store withBlock:nil];

            TestImportProcess *redImport = [redType enqueueImport];
            Report *importReport = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());
            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(importReport);

            [notifications removeObserver:observer];
        });

        it(@"does not create multiple reports while the archive is extracting", ^{

            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DICEExtractReportOperation *extract;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    NSLog(@"blocking extract operation");
                    [extract block];
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            NSArray *reports1 = [[store loadReports] copy];

            expect(reports1.count).to.equal(1);

            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());

            NSUInteger opCount = importQueue.operationCount;

            NSArray *reports2 = [[store loadReports] copy];

            expect(reports2.count).to.equal(reports1.count);
            expect(importQueue.operationCount).to.equal(opCount);

            TestImportProcess *blueImport = [blueType enqueueImport];

            NSLog(@"unblocking extract operation");
            [extract unblock];
            
            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"parses the report descriptor if present in base dir as metadata.json", ^{
            [fileManager setContentsOfReportsDir:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", nil];
            fileManager.contentsAtPath[[reportsDir.path stringByAppendingPathComponent:@"blue_base/metadata.json"]] =
                [@"{\"title\": \"Title From Descriptor\", \"description\": \"Summary from descriptor\"}"
                    dataUsingEncoding:NSUTF8StringEncoding];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:baseDir];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(report.title).to.equal(@"Title From Descriptor");
            expect(report.summary).to.equal(@"Summary from descriptor");
        });

        it(@"parses the report descriptor if present in base dir as dice.json", ^{
            [fileManager setContentsOfReportsDir:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", nil];
            fileManager.contentsAtPath[[reportsDir.path stringByAppendingPathComponent:@"blue_base/dice.json"]] =
                [@"{\"title\": \"Title From Descriptor\", \"description\": \"Summary from descriptor\"}"
                    dataUsingEncoding:NSUTF8StringEncoding];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:baseDir];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(report.title).to.equal(@"Title From Descriptor");
            expect(report.summary).to.equal(@"Summary from descriptor");
        });

        it(@"prefers dice.json to metadata.json", ^{
            [fileManager setContentsOfReportsDir:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", @"blue_base/dice.json", nil];
            fileManager.contentsAtPath[[reportsDir.path stringByAppendingPathComponent:@"blue_base/dice.json"]] =
                [@"{\"title\": \"Title From dice.json\", \"description\": \"Summary from dice.json\"}"
                    dataUsingEncoding:NSUTF8StringEncoding];
            fileManager.contentsAtPath[[reportsDir.path stringByAppendingPathComponent:@"blue_base/metadata.json"]] =
                [@"{\"title\": \"Title From metadata.json\", \"description\": \"Summary from metadata.json\"}"
                    dataUsingEncoding:NSUTF8StringEncoding];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:baseDir];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(report.title).to.equal(@"Title From dice.json");
            expect(report.summary).to.equal(@"Summary from dice.json");
        });

        it(@"sets a nil summary if the report descriptor is unavailable", ^{
            [fileManager setContentsOfReportsDir:@"blue_base/", @"blue_base/index.blue", nil];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:baseDir];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(report.summary).to.beNil();
        });

        it(@"works if the import process changes the report url", ^{
            [fileManager setContentsOfReportsDir:@"blue_base/", @"blue_base/index.blue", nil];
            TestImportProcess *blueImport = [blueType enqueueImport];
            blueImport.steps = @[
                [NSBlockOperation blockOperationWithBlock:^{
                    blueImport.report.rootResource = [reportsDir URLByAppendingPathComponent:@"blue_base/index.blue"];
                }],
                [[NSBlockOperation blockOperationWithBlock:^{}] block]
            ];

            Report *report1 = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]];

            assertWithTimeout(1.0, thatEventually(report1.rootResource), equalTo([reportsDir URLByAppendingPathComponent:@"blue_base/index.blue"]));

            Report *report2 = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]];

            expect(report2).to.beIdenticalTo(report1);
            expect(store.reports.count).to.equal(1);
            expect(store.reports.firstObject).to.beIdenticalTo(report1);

            [blueImport.steps[1] unblock];

            assertWithTimeout(1.0, thatEventually(@(report1.isEnabled)), isTrue());

            expect(store.reports.count).to.equal(1);
            expect(store.reports.firstObject).to.beIdenticalTo(report1);

            report2 = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]];

            expect(report2).to.beIdenticalTo(report1);
            expect(report2.isEnabled).to.equal(YES);
        });

        it(@"sets the base dir when there is one", ^{

            [fileManager setContentsOfReportsDir:@"blue_base/", @"blue_base/index.blue", nil];
            TestImportProcess *blueImport = [[blueType enqueueImport] block];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]];

            expect(report.baseDir).to.equal([reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]);
            expect(report.rootResource).to.equal(report.baseDir);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(report.baseDir).to.equal([reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]);
            expect(report.rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"blue_base/index.blue"]);
        });

        it(@"does not set the base dir for a single file", ^{

            [fileManager setContentsOfReportsDir:@"dingle.blue", nil];
            TestImportProcess *blueImport = [[blueType enqueueImport] block];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"dingle.blue"]];

            expect(report.baseDir).to.beNil();
            expect(report.rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"dingle.blue"]);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(report.baseDir).to.beNil();
            expect(report.rootResource).to.equal([reportsDir URLByAppendingPathComponent:@"dingle.blue"]);
        });

        it(@"posts a failure notification if no report type matches the content", ^{

            [fileManager setContentsOfReportsDir:@"oops.der", nil];
            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"oops.dir"]];

            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(1));

            NSNotification *note = obs.received.firstObject.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
        });

        it(@"can retry a failed import after deleting the report", ^{

            NSURL *url = [reportsDir URLByAppendingPathComponent:@"oops.bloo"];
            [fileManager setContentsOfReportsDir:url.lastPathComponent, nil];
            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            NSNotification *note = obs.received.firstObject.notification;

            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);

            [store deleteReport:report];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:url.path] || [store.reports containsObject:report])), isFalse());

            [fileManager setContentsOfReportsDir:url.lastPathComponent, nil];

            Report *retry = [store attemptToImportReportFromResource:url];

            expect(retry).toNot.beIdenticalTo(report);

            assertWithTimeout(1.0, thatEventually(@(retry.isImportFinished)), isTrue());

            expect(retry.importStatus).to.equal(ReportImportStatusFailed);
            expect(obs.received).to.haveCountOf(2);
            expect(obs.received[0].notification.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(obs.received[1].notification.userInfo[@"report"]).to.beIdenticalTo(retry);
        });

        xit(@"passees the content match predicate to the import process", ^{
            /*
             TODO: Allow the ReportContentMatchPredicate to pass information to
             the ImportProcess about what was found in the archive.  this will
             help support alternatives to the standard index.html assumption by
             potentially allowing the ImportProcess to rename or symlink html
             resources found during the archive entry enumeration.
             Also the HtmlReportType should do a breadth first search for html
             files, or at least in the base dir.  also maybe restore the fail-
             fast element of the ReportTypeMatchPredicate, e.g., if index.html
             exists at the root, stop immediately.  Possibly reuse the ReportContentMatchPredicate
             for enumerating file system contents.
             */
            failure(@"do it");
        });

    });

    describe(@"importing report archives", ^{

        it(@"creates a base dir if the archive has no base dir", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dicex" isDirectory:YES];
            [fileManager setOnCreateDirectoryAtURL:^BOOL(NSURL *url, BOOL intermediates, NSError **error) {
                expect(url).to.equal(baseDir);
                return [url isEqual:baseDir];
            }];
            [fileManager setOnCreateFileAtPath:^BOOL(NSString *path) {
                expect(path).to.equal([baseDir.path stringByAppendingPathComponent:@"index.blue"]);
                return [path isEqualToString:[baseDir.path stringByAppendingPathComponent:@"index.blue"]];
            }];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not create a new base dir if archive has base dir", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];

            [fileManager setOnCreateDirectoryAtURL:^BOOL(NSURL *path, BOOL intermediates, NSError **error) {
                expect(path).to.equal(baseDir);
                return [path isEqual:baseDir];
            }];
            [fileManager setOnCreateFileAtPath:^BOOL(NSString *path) {
                expect(path).to.equal([baseDir.path stringByAppendingPathComponent:@"index.blue"]);
                return [path isEqualToString:[baseDir.path stringByAppendingPathComponent:@"index.blue"]];
            }];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes the base dir to the extracted base dir before extracting", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block NSURL *baseDirBeforeExtracting = nil;
            __block DICEExtractReportOperation *extract = nil;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    baseDirBeforeExtracting = extract.report.baseDir;
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(blueImport.report.baseDir).to.equal(baseDir);
            expect(baseDirBeforeExtracting).to.equal(baseDir);
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes the base dir to the created base dir before extracting", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dicex" isDirectory:YES];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block NSURL *baseDirBeforeExtracting = nil;
            __block DICEExtractReportOperation *extract = nil;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    baseDirBeforeExtracting = extract.report.baseDir;
                }
            };

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(blueImport.report.baseDir).to.equal(baseDir);
            expect(baseDirBeforeExtracting).to.equal(baseDir);
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes the report url and base dir to the extracted base dir", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(blueImport.report.baseDir).to.equal(baseDir);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes the report url and base dir to the created base dir", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dicex" isDirectory:YES];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(blueImport.report.baseDir).to.equal(baseDir);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"removes the archive file after extracting the contents", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.equal(YES);

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
            
            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.equal(NO);
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes import status to extracting and posts update notification", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DICEExtractReportOperation *extract;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [extract block];
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportExtractProgress on:notifications from:store withBlock:nil];

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToUnsignedInteger(1));

            ReceivedNotification *received = observer.received.firstObject;
            NSNotification *note = received.notification;

            expect(received.wasMainThread).to.equal(YES);
            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusExtracting);

            [extract unblock];

            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"posts notifications about extract progress", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:(1 << 20)]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            [blueType enqueueImport];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];
            NSMutableArray<NSNotification *> *extractUpdates = [NSMutableArray array];
            __block NSNotification *finished = nil;
            [store.notifications addObserverForName:ReportNotification.reportExtractProgress object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
                [extractUpdates addObject:note];
            }];
            [store.notifications addObserverForName:ReportNotification.reportImportFinished object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
                finished = note;
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(finished), notNilValue());

            expect(extractUpdates.count).to.beGreaterThan(10);
            expect(extractUpdates.lastObject.userInfo[@"percentExtracted"]).to.equal(@100);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not create multiple reports while the archive is extracting", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DICEExtractReportOperation *extract;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    NSLog(@"blocking extract operation");
                    [extract block];
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            Report *report1 = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());

            NSUInteger opCount = importQueue.operationCount;

            Report *report2 = [store attemptToImportReportFromResource:archiveUrl];

            expect(report2).to.beIdenticalTo(report1);
            expect(store.reports.count).to.equal(1);
            expect(importQueue.operationCount).to.equal(opCount);

            TestImportProcess *blueImport = [blueType enqueueImport];
            // [blueImport block];
            NSLog(@"unblocking extract operation");
            [extract unblock];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not start an import process if the extraction fails", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    *errOut = [[NSError alloc] initWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"error for test"}];
                    return nil;
                };
            }];

            // intentionally do not enqueue import process
            // TestImportProcess *blueImport = [blueType enqueueImport];

            __block DICEExtractReportOperation *extract;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToUnsignedInteger(ReportImportStatusFailed));

            expect(extract.isFinished).to.equal(YES);
            expect(extract.wasSuccessful).to.equal(NO);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"posts failure notification if extract fails", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    *errOut = [[NSError alloc] initWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"error for test"}];
                    return nil;
                };
            }];

            // intentionally do not enqueue import process
            // TestImportProcess *blueImport = [blueType enqueueImport];

            __block DICEExtractReportOperation *extract;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];

            Report *report = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToUnsignedInteger(1));
            
            expect(extract.isFinished).to.equal(YES);
            expect(extract.wasSuccessful).to.equal(NO);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
            expect(report.summary).to.equal(@"Failed to extract archive contents");

            ReceivedNotification *received = observer.received.lastObject;
            NSNotification *note = received.notification;

            expect(received.wasMainThread).to.equal(YES);
            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
            
            [NSFileHandle deswizzleAllClassMethods];
        });

    });

#pragma mark downloading

    describe(@"downloading content", ^{

        it(@"starts a download when importing from an http url", ^{
        
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report"];
            Report *report = [store attemptToImportReportFromResource:url];

            [verify(downloadManager) downloadUrl:url];
            expect(report.importStatus).to.equal(ReportImportStatusDownloading);
            expect(store.reports).to.contain(report);
        });

        it(@"starts a download when importing from an https url", ^{

            NSURL *url = [NSURL URLWithString:@"https://dice.com/report"];
            Report *report = [store attemptToImportReportFromResource:url];

            [verify(downloadManager) downloadUrl:url];
            expect(report.importStatus).to.equal(ReportImportStatusDownloading);
            expect(store.reports).to.contain(report);
        });

        it(@"posts a report added notification before the download begins", ^{

            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportAdded on:store.notifications from:store withBlock:nil];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(1));

            ReceivedNotification *received = obs.received.firstObject;
            NSNotification *note = received.notification;
            NSDictionary *userInfo = note.userInfo;

            expect(userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.importStatus).to.equal(ReportImportStatusDownloading);
        });

        it(@"posts download progress notifications", ^{

            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:nil];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 12345;
            Report *report = [store attemptToImportReportFromResource:url];
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];

            expect(obs.received).to.haveCountOf(1);

            ReceivedNotification *received = obs.received.firstObject;
            NSNotification *note = received.notification;
            NSDictionary *userInfo = note.userInfo;

            expect(userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.downloadProgress).to.equal(1);
        });

        it(@"posts download finished notification", ^{

            TestImportProcess *import = [blueType enqueueImport];
            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadComplete on:store.notifications from:store withBlock:nil];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 999999;
            download.downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
            Report *report = [store attemptToImportReportFromResource:url];

            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:download.downloadedFile];
            download.wasSuccessful = YES;
            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(@(import.isFinished)), isTrue());

            ReceivedNotification *received = obs.received.firstObject;
            NSNotification *note = received.notification;
            NSDictionary *userInfo = note.userInfo;

            expect(obs.received).to.haveCountOf(1);
            expect(userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.downloadProgress).to.equal(100);
        });

        it(@"does not post a progress notification if the percent complete did not change", ^{

            __block NSInteger lastProgress = 0;
            NotificationRecordingObserver *obs = [[NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:^(NSNotification *notification) {
                if (![ReportNotification.reportDownloadProgress isEqualToString:notification.name]) {
                    return;
                }
                Report *report = notification.userInfo[@"report"];
                if (lastProgress == report.downloadProgress) {
                    failure([NSString stringWithFormat:@"duplicate progress notifications: %@", @(lastProgress)]);
                }
                lastProgress = report.downloadProgress;
            }] observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];

            TestImportProcess *import = [blueType enqueueImport];
            import.steps = @[[NSBlockOperation blockOperationWithBlock:^{}]];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            Report *report = [store attemptToImportReportFromResource:url];

            download.bytesReceived = 12345;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 12500;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 99999;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 999999;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            download.downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
            [store downloadManager:downloadManager willFinishDownload:download movingToFile:download.downloadedFile];
            download.wasSuccessful = YES;
            [store downloadManager:downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            ReceivedNotification *received = obs.received.lastObject;
            NSNotification *note = received.notification;
            NSDictionary *userInfo = note.userInfo;

            expect(obs.received).to.haveCountOf(4);
            expect(obs.received.lastObject.notification.name).to.equal(ReportNotification.reportDownloadComplete);
            expect(userInfo[@"report"]).to.beIdenticalTo(report);
            expect(report.downloadProgress).to.equal(100);
        });

        it(@"does not post a progress notification about a url it is not importing", ^{

            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:nil];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 999999;
            [store attemptToImportReportFromResource:url];
            DICEDownload *foreignDownload = [[DICEDownload alloc] initWithUrl:[NSURL URLWithString:@"http://not.a.report/i/know/about.blue"]];

            [store downloadManager:store.downloadManager didReceiveDataForDownload:foreignDownload];
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];

            expect(obs.received).to.haveCountOf(1);
        });

        it(@"begins an import for the same report after the download is complete", ^{

            TestImportProcess *blueImport = [[blueType enqueueImport] block];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            Report *report = [store attemptToImportReportFromResource:url];
            download.bytesReceived = 555555;
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 999999;
            url = [reportsDir URLByAppendingPathComponent:@"report.blue"];
            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:url];
            [fileManager createFileAtPath:url.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
            download.wasSuccessful = YES;
            download.downloadedFile = url;
            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(@(report.importStatus)), equalToInteger(ReportImportStatusImporting));

            expect(blueImport.report).to.beIdenticalTo(report);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(blueImport.isFinished)), isTrue());
        });

        it(@"responds to failed downloads", ^{

            TestImportProcess *import = [blueType enqueueImport];
            import.steps = @[[NSBlockOperation blockOperationWithBlock:^{
                failure(@"erroneously started import process for failed download");
            }]];
            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:store.notifications from:store withBlock:nil];
            [obs observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];
            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
            download.bytesExpected = 999999;
            download.bytesReceived = 0;
            download.downloadedFile = nil;
            download.wasSuccessful = NO;
            download.httpResponseCode = 503;

            Report *report = [store attemptToImportReportFromResource:url];

            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(obs.received.lastObject.notification.name), equalTo(ReportNotification.reportImportFinished));

            expect(obs.received).to.haveCountOf(1);
            expect(obs.received.lastObject.notification.name).to.equal(ReportNotification.reportImportFinished);
            expect(report.importStatus).to.equal(ReportImportStatusFailed);
            expect(report.isEnabled).to.beFalsy();
        });

        it(@"can import a downloaded archive file", ^{

            NSURL *downloadUrl = [NSURL URLWithString:@"http://dice.com/report.zip"];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:downloadUrl];
            download.bytesExpected = 999999;
            Report *report = [store attemptToImportReportFromResource:downloadUrl];
            download.bytesReceived = 555555;
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];
            download.bytesReceived = 999999;
            NSURL *downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.zip"];
            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:downloadedFile];
            [fileManager createFileAtPath:downloadUrl.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
            download.wasSuccessful = YES;
            download.downloadedFile = downloadedFile;
            download.mimeType = @"application/zip";
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:999999 sizeExtracted:999999]
            ] archiveUrl:downloadedFile archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:downloadedFile withUti:kUTTypeZipArchive]) willReturn:archive];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];
            TestImportProcess *blueImport = [blueType enqueueImport];

            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isImportFinished)), isTrue());

            expect(report.importStatus).to.equal(ReportImportStatusSuccess);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"can re-download the same url after failing to import a downloaded file", ^{

            failure(@"do it");
        });

        it(@"creates report records for in-progress background downloads when the app starts", ^{

            failure(@"do it");
        });

    });

    describe(@"background task handling", ^{

        it(@"starts and ends background task for importing reports", ^{
            [fileManager setContentsOfReportsDir:@"test.red", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:notNilValue() forArgument:1] willReturnUnsignedInteger:999];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [verify(app) endBackgroundTask:999];
        });

        it(@"begins and ends only one background task for multiple concurrent imports", ^{
            [fileManager setContentsOfReportsDir:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];
            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:notNilValue() forArgument:1] willReturnUnsignedInteger:999];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.blue"]];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [verifyCount(app, never()) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:999];

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verifyCount(app, times(1)) endBackgroundTask:999];
        });

        it(@"begins and ends only one background task for loading reports", ^{
            [fileManager setContentsOfReportsDir:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];
            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:notNilValue() forArgument:1] willReturnUnsignedInteger:999];

            [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [verifyCount(app, times(1)) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:999];

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verifyCount(app, never()) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [verifyCount(app, times(1)) endBackgroundTask:999];
        });
        
        it(@"saves the import state and stops the background task when the OS calls the expiration handler", ^{

            // TODO: verify the archive extract points get saved when that's implemented

            [fileManager setContentsOfReportsDir:@"test.red", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            NSOperation *step = [[NSBlockOperation blockOperationWithBlock:^{}] block];
            redImport.steps = @[step];
            HCArgumentCaptor *expirationBlockCaptor = [[HCArgumentCaptor alloc] init];
            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:expirationBlockCaptor forArgument:1] willReturnUnsignedInteger:999];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.steps.firstObject.isExecuting)), isTrue());

            void (^expirationBlock)() = expirationBlockCaptor.value;
            expirationBlock();

            [redImport.steps.firstObject unblock];

            assertWithTimeout(1.0, thatEventually(@(!step.isExecuting && step.isCancelled)), isTrue());

            [verify(app) endBackgroundTask:999];
        });

        it(@"ends the background task when the last import fails", ^{

            [fileManager setContentsOfReportsDir:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            TestImportProcess *blueImport = [blueType enqueueImport];
            blueImport.steps = @[[[NSBlockOperation blockOperationWithBlock:^{}] block]];

            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:anything() forArgument:1] willDo:^id(NSInvocation *invoc) {
                return @999;
            }];

            [[givenVoid([app endBackgroundTask:0]) withMatcher:anything()] willDo:^id(NSInvocation *invoc) {
                NSNumber *taskIdArg = invoc.mkt_arguments[0];
                if (taskIdArg.unsignedIntegerValue != 999) {
                    failure(@"ended wrong task id");
                }
                return nil;
            }];

            __block Report *finishedReport;
            NotificationRecordingObserver *observer = [NotificationRecordingObserver
                observe:[ReportNotification reportImportFinished] on:notifications from:store withBlock:^(NSNotification *notification) {
                    finishedReport = notification.userInfo[@"report"];
                }];

            [store loadReports];

            assertWithTimeout(1.0, thatEventually(blueImport.report), notNilValue());
            assertWithTimeout(1.0, thatEventually(redImport.report), notNilValue());
            assertWithTimeout(1.0, thatEventually(finishedReport), sameInstance(redImport.report));

            [blueImport cancel];
            [blueImport.steps.firstObject unblock];

            assertWithTimeout(1.0, thatEventually(@(finishedReport == blueImport.report)), isTrue());

            expect(observer.received.count).to.equal(2);
            [verify(app) endBackgroundTask:999];

            [notifications removeObserver:observer];
        });

    });

    describe(@"ignoring reserved files in reports dir", ^{

        it(@"can add exclusions", ^{

            [blueType enqueueImport];
            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"not-excluded.blue"]];

            expect(report).toNot.beNil();
            expect(store.reports).to.contain(report);

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            [store addReportsDirExclusion:[NSPredicate predicateWithFormat:@"self.lastPathComponent like %@", @"excluded.blue"]];

            [blueType enqueueImport];
            report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"excluded.blue"]];

            expect(report).to.beNil();
            expect(store.reports).to.haveCountOf(1);
        });

    });

    describe(@"deleting reports", ^{

        __block NSURL *trashDir;
        __block Report *singleResourceReport;
        __block Report *baseDirReport;

        beforeEach(^{
            trashDir = [reportsDir URLByAppendingPathComponent:@".dice.trash" isDirectory:YES];
            [fileManager setContentsOfReportsDir:@"standalone.red", @"blue_base/", @"blue_base/index.blue", @"blue_base/icon.png", nil];
            ImportProcess *redImport = [redType enqueueImport];
            ImportProcess *blueImport = [blueType enqueueImport];
            NSArray<Report *> *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(reports), everyItem(hasProperty(@"isImportFinished", isTrue())));

            singleResourceReport = redImport.report;
            baseDirReport = blueImport.report;
        });

        it(@"performs delete operations at a lower priority and quality of service", ^{

            __block MoveFileOperation *moveToTrash;
            __block DeleteFileOperation *deleteFromTrash;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveToTrash = (MoveFileOperation *)op;
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteFromTrash = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@(moveToTrash != nil && deleteFromTrash != nil)), isTrue());

            expect(moveToTrash.queuePriority).to.equal(NSOperationQueuePriorityHigh);
            expect(moveToTrash.qualityOfService).to.equal(NSQualityOfServiceUserInitiated);
            expect(deleteFromTrash.queuePriority).to.equal(NSOperationQueuePriorityLow);
            expect(deleteFromTrash.qualityOfService).to.equal(NSQualityOfServiceBackground);

            assertWithTimeout(1.0, thatEventually(@(singleResourceReport.importStatus)), equalToUnsignedInteger(ReportImportStatusDeleted));
        });

        it(@"immediately disables the report, sets its summary, status, and sends change notification", ^{

            expect(store.reports).to.contain(singleResourceReport);
            expect(singleResourceReport.isEnabled).to.equal(YES);

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportChanged on:notifications from:store withBlock:nil];
            importQueue.suspended = YES;

            [store deleteReport:singleResourceReport];

            expect(singleResourceReport.isEnabled).to.equal(NO);
            expect(singleResourceReport.importStatus).to.equal(ReportImportStatusDeleting);
            expect(singleResourceReport.statusMessage).to.equal(@"Deleting content...");
            expect(observer.received.count).to.equal(1);
            expect(observer.received.firstObject.notification.userInfo[@"report"]).to.beIdenticalTo(singleResourceReport);

            importQueue.suspended = NO;

            assertWithTimeout(1.0, thatEventually(store.reports), isNot(hasItem(singleResourceReport)));
        });

        it(@"removes the report from the list after moving to the trash dir", ^{

            __block MoveFileOperation *moveOp;
            __block DeleteFileOperation *deleteOp;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveOp = (MoveFileOperation *)[op block];
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteOp = (DeleteFileOperation *)[op block];
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(moveOp), isNot(nilValue()));

            [moveOp unblock];

            assertWithTimeout(1.0, thatEventually(@(moveOp.isFinished)), isTrue());
            assertWithTimeout(1.0, thatEventually(store.reports), isNot(hasItem(singleResourceReport)));

            [deleteOp unblock];
        });

        it(@"sets the report status when finished deleting", ^{

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@(singleResourceReport.importStatus)), equalToUnsignedInteger(ReportImportStatusDeleted));
        });

        it(@"creates the trash dir if it does not exist", ^{

            BOOL isDir;
            expect([fileManager fileExistsAtPath:trashDir.path isDirectory:(BOOL * _Nullable)&isDir]).to.equal(NO);
            expect(isDir).to.equal(NO);

            __block BOOL createdOnBackgroundThread = NO;
            fileManager.onCreateDirectoryAtURL = ^BOOL(NSURL *dir, BOOL createIntermediates, NSError *__autoreleasing *err) {
                if ([dir.path hasPrefix:trashDir.path]) {
                    createdOnBackgroundThread = !NSThread.isMainThread;
                }
                return YES;
            };

            __block DeleteFileOperation *deleteOp;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteOp = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:trashDir.path isDirectory:(BOOL * _Nullable)&isDir] && isDir)), isTrue());
            assertWithTimeout(1.0, thatEventually(@(deleteOp.isFinished)), isTrue());

            expect(createdOnBackgroundThread).to.beTruthy();
        });

        it(@"does not load a report for the trash dir", ^{

            [fileManager createDirectoryAtURL:trashDir withIntermediateDirectories:YES attributes:nil error:NULL];

            NSArray *reports = [store loadReports];

            expect(reports).to.haveCountOf(2);

            assertWithTimeout(1.0, thatEventually(reports), everyItem(hasProperty(@"isImportFinished", @YES)));
        });

        it(@"moves the base dir to a unique trash dir", ^{

            __block MoveFileOperation *moveToTrash;
            __block DeleteFileOperation *deleteFromTrash;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveToTrash = (MoveFileOperation *)op;
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteFromTrash = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:baseDirReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:baseDirReport.baseDir.path])), isFalse());

            expect(moveToTrash).toNot.beNil();
            expect(moveToTrash.sourceUrl).to.equal(baseDirReport.baseDir);
            expect(moveToTrash.destUrl.path).to.beginWith(trashDir.path);

            NSString *reportRelPath = [baseDirReport.baseDir.path pathRelativeToPath:reportsDir.path];
            NSString *reportParentInTrash = [moveToTrash.destUrl.path pathRelativeToPath:trashDir.path];
            reportParentInTrash = reportParentInTrash.pathComponents.firstObject;
            NSUUID *uniqueTrashDirName = [[NSUUID alloc] initWithUUIDString:reportParentInTrash];

            expect(moveToTrash.destUrl.path).to.endWith(reportRelPath);
            expect(uniqueTrashDirName).toNot.beNil();

            assertWithTimeout(1.0, thatEventually(@(deleteFromTrash.isFinished)), isTrue());

            expect(deleteFromTrash.fileUrl).to.equal([trashDir URLByAppendingPathComponent:reportParentInTrash isDirectory:YES]);
        });

        it(@"moves the root resource to a unique trash dir when there is no base dir", ^{

            __block MoveFileOperation *moveToTrash;
            __block DeleteFileOperation *deleteFromTrash;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveToTrash = (MoveFileOperation *)op;
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteFromTrash = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:singleResourceReport.rootResource.path])), isFalse());

            expect(moveToTrash).toNot.beNil();
            expect(moveToTrash.sourceUrl).to.equal(singleResourceReport.rootResource);
            expect(moveToTrash.destUrl.path).to.beginWith(trashDir.path);

            NSString *reportRelPath = [singleResourceReport.rootResource.path pathRelativeToPath:reportsDir.path];
            NSString *reportParentInTrash = [moveToTrash.destUrl.path pathRelativeToPath:trashDir.path];
            reportParentInTrash = reportParentInTrash.pathComponents.firstObject;
            NSUUID *uniqueTrashDirName = [[NSUUID alloc] initWithUUIDString:reportParentInTrash];

            expect(moveToTrash.destUrl.path).to.endWith(reportRelPath);
            expect(uniqueTrashDirName).toNot.beNil();

            assertWithTimeout(1.0, thatEventually(@(deleteFromTrash.isFinished)), isTrue());

            expect(deleteFromTrash.fileUrl).to.equal([trashDir URLByAppendingPathComponent:reportParentInTrash isDirectory:YES]);
        });

        it(@"cannot delete a report while importing", ^{

            NSURL *importingReportUrl = [reportsDir URLByAppendingPathComponent:@"importing.red"];
            [fileManager createFileAtPath:importingReportUrl.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
            TestImportProcess *process = [[redType enqueueImport] block];

            Report *importingReport = [store attemptToImportReportFromResource:importingReportUrl];

            assertWithTimeout(1.0, thatEventually(@(importingReport.importStatus)), equalToUnsignedInteger(ReportImportStatusImporting));

            expect(importingReport.importStatus).to.equal(ReportImportStatusImporting);

            [store deleteReport:importingReport];

            expect(importingReport.importStatus).to.equal(ReportImportStatusImporting);

            [process unblock];

            assertWithTimeout(1.0, thatEventually(@(importingReport.isImportFinished)), isTrue());
        });

        it(@"sends a notification when a report is removed from the reports list", ^{

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportRemoved on:store.notifications from:store withBlock:^(NSNotification *notification) {
                expect(store.reports).notTo.contain(singleResourceReport);
            }];
            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(1));

            ReceivedNotification *removed = observer.received.firstObject;

            expect(removed.notification.userInfo[@"report"]).to.beIdenticalTo(singleResourceReport);
        });

    });

    describe(@"notifications", ^{

        it(@"works as expected", ^{
            NSMutableArray<NSNotification *> *notes = [NSMutableArray array];
            NSNotificationCenter *notifications = [[NSNotificationCenter alloc] init];
            [notifications addObserverForName:@"test.notification" object:self queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                [notes addObject:note];
            }];
            NotificationRecordingObserver *recorder = [NotificationRecordingObserver observe:@"test.notification" on:notifications from:self withBlock:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [notifications postNotificationName:@"test.notification" object:self];
            });
            
            assertWithTimeout(1.0, thatEventually(@(notes.count)), equalToUnsignedInteger(1));

            assertWithTimeout(1.0, thatEventually(@(recorder.received.count)), equalToUnsignedInteger(1));
        });

    });

});

SpecEnd
