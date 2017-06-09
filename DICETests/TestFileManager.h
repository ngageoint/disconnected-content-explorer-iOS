
#import <Foundation/Foundation.h>


@interface TestFileManager : NSFileManager

@property (nonnull, nonatomic) NSString *workingDir;
@property (nullable, nonatomic) BOOL (^onCreateFileAtPath)(NSString * _Nonnull path);
@property (nullable, nonatomic) BOOL (^onCreateDirectoryAtPath)(NSString * _Nonnull path, BOOL createIntermediates, NSError * _Nullable * _Nullable error);
@property (nullable, nonatomic) BOOL (^onMoveItemAtPath)(NSString * _Nonnull sourcePath, NSString * _Nonnull destPath, NSError * _Nullable * _Nullable error);

/**
 * Create files and directories relative to the working directory for the given path strings.
 * Indicate a directory by a trailing slash, e.g., relative_dir/.  This method will create
 * any necessary intermediate directories.  Throw NSInvalidArgumentException if creating any
 * of the given items fails.
 */
- (nonnull instancetype)createPaths:(nonnull NSString *)path, ... NS_REQUIRES_NIL_TERMINATION;
- (nonnull instancetype)createFilePath:(nonnull NSString *)path contents:(nullable NSData *)data;

@end
