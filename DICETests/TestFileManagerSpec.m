//
//  TestFileManagerSpec.m
//  DICE
//
//  Created by Robert St. John on 5/13/17.
//  Copyright 2017 mil.nga. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#import "TestFileManager.h"


SpecBegin(TestFileManager)

describe(@"TestFileManager", ^{

    __block TestFileManager *fileManager;
    __block NSURL *rootDir;
    __block BOOL isDir;

    beforeEach(^{
        rootDir = [NSURL fileURLWithPath:@"/dice/" isDirectory:YES];
        fileManager = [[[TestFileManager alloc] init] setWorkingDirChildren:@"dice/", nil];
        fileManager.workingDir = rootDir.path;
    });

    it(@"works", ^{

        NSLog(@"SANITY CHECK");

        [fileManager setWorkingDirChildren:@"hello.txt", @"dir/", nil];

        expect([fileManager fileExistsAtPath:rootDir.path isDirectory:&isDir]).to.beTruthy();
        expect(isDir).to.beTruthy();

        expect([fileManager fileExistsAtPath:[rootDir URLByAppendingPathComponent:@"hello.txt"].path isDirectory:&isDir]).to.beTruthy();
        expect(isDir).to.beFalsy();
        expect([fileManager fileExistsAtPath:[rootDir URLByAppendingPathComponent:@"dir" isDirectory:YES].path isDirectory:&isDir]).to.beTruthy();
        expect(isDir).to.beTruthy();
        expect([fileManager fileExistsAtPath:[rootDir URLByAppendingPathComponent:@"dir"].path isDirectory:&isDir]).to.beTruthy();
        expect(isDir).to.beTruthy();

        expect([fileManager removeItemAtURL:[rootDir URLByAppendingPathComponent:@"does_not_exist"] error:NULL]).to.beFalsy();
        expect([fileManager removeItemAtURL:[rootDir URLByAppendingPathComponent:@"dir"] error:NULL]).to.beTruthy();
        expect([fileManager fileExistsAtPath:[rootDir URLByAppendingPathComponent:@"dir"].path]).to.beFalsy();

        expect([fileManager createFileAtPath:[rootDir URLByAppendingPathComponent:@"new.txt"].path contents:nil attributes:nil]).to.beTruthy();
        expect([fileManager fileExistsAtPath:[rootDir URLByAppendingPathComponent:@"new.txt"].path isDirectory:&isDir]).to.beTruthy();
        expect(isDir).to.beFalsy();
        NSUInteger pathCount = [fileManager contentsOfDirectoryAtPath:rootDir.path error:NULL].count;
        expect([fileManager createFileAtPath:[rootDir.path stringByAppendingPathComponent:@"new.txt"] contents:nil attributes:nil]).to.beTruthy();
        expect([fileManager createDirectoryAtURL:[rootDir URLByAppendingPathComponent:@"new.txt"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.beFalsy();
        expect([fileManager contentsOfDirectoryAtPath:rootDir.path error:NULL]).to.haveCountOf(pathCount);

        expect([fileManager createDirectoryAtURL:[rootDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.beTruthy();
        expect([fileManager fileExistsAtPath:[rootDir URLByAppendingPathComponent:@"dir"].path isDirectory:&isDir]).to.beTruthy();
        expect(isDir).to.beTruthy();
        pathCount = [fileManager contentsOfDirectoryAtPath:rootDir.path error:NULL].count;
        expect([fileManager createFileAtPath:[rootDir.path stringByAppendingPathComponent:@"dir"] contents:nil attributes:nil]).to.beFalsy();
        expect([fileManager createDirectoryAtURL:[rootDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.beTruthy();
        expect([fileManager createDirectoryAtURL:[rootDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:NO attributes:nil error:NULL]).to.beFalsy();
        expect([fileManager contentsOfDirectoryAtPath:rootDir.path error:NULL]).to.haveCountOf(pathCount);

        NSString *intermediates = [rootDir.path stringByAppendingPathComponent:@"dir1/dir2/dir3"];
        expect([fileManager createDirectoryAtPath:intermediates withIntermediateDirectories:NO attributes:nil error:NULL]).to.beFalsy();
        expect([fileManager fileExistsAtPath:intermediates]).to.beFalsy();
        expect([fileManager fileExistsAtPath:intermediates.stringByDeletingLastPathComponent]).to.beFalsy();
        expect([fileManager fileExistsAtPath:intermediates.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent]).to.beFalsy();
        expect([fileManager createDirectoryAtPath:intermediates withIntermediateDirectories:YES attributes:nil error:NULL]).to.beTruthy();
        expect([fileManager fileExistsAtPath:intermediates]).to.beTruthy();
        expect([fileManager fileExistsAtPath:intermediates.stringByDeletingLastPathComponent]).to.beTruthy();
        expect([fileManager fileExistsAtPath:intermediates.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent]).to.beTruthy();
        expect([fileManager createFileAtPath:@"/not/in/rootDir.txt" contents:nil attributes:nil]).to.beFalsy();
        expect([fileManager fileExistsAtPath:@"/not/in/rootDir.txt" isDirectory:&isDir]).to.beFalsy();
        expect(isDir).to.beFalsy();

        expect([fileManager fileExistsAtPath:nil]).to.beFalsy();
    });

    describe(@"file contents", ^{

        it(@"sets the contents of a child of root dir", ^{

            NSString *contentsPath = [rootDir.path stringByAppendingPathComponent:@"contents.txt"];
            NSData *contents = [@"ABC123" dataUsingEncoding:NSUTF8StringEncoding];
            [fileManager createFilePath:@"contents.txt" contents:[contents copy]];

            expect([fileManager contentsAtPath:contentsPath]).to.equal([contents copy]);
            expect([fileManager fileExistsAtPath:contentsPath isDirectory:&isDir]);
            expect(isDir).to.beFalsy();
        });

        it(@"sets the contents of a file in a subdir", ^{

            NSString *contentsPath = [rootDir.path stringByAppendingPathComponent:@"dir_prefix/contents.txt"];
            NSData *contents = [@"456DEF" dataUsingEncoding:NSUTF8StringEncoding];
            [fileManager createFilePath:@"dir_prefix/contents.txt" contents:[contents copy]];

            expect([fileManager fileExistsAtPath:contentsPath isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir_prefix"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager contentsAtPath:contentsPath]).to.equal([contents copy]);
            expect([fileManager contentsAtPath:contentsPath.stringByDeletingLastPathComponent]).to.beNil();
        });

        it(@"overwrites contents of a file", ^{

            NSString *contentsPath = [rootDir.path stringByAppendingPathComponent:@"dir_prefix/contents.txt"];
            NSData *contents = [@"ABC123" dataUsingEncoding:NSUTF8StringEncoding];
            [fileManager createFilePath:@"dir_prefix/contents.txt" contents:[contents copy]];

            expect([fileManager fileExistsAtPath:contentsPath isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir_prefix"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager contentsAtPath:contentsPath]).to.equal([contents copy]);
            expect([fileManager contentsAtPath:contentsPath.stringByDeletingLastPathComponent]).to.beNil();

            NSData *overwrite = [@"overwrite" dataUsingEncoding:NSUTF8StringEncoding];
            [fileManager createFilePath:@"dir_prefix/contents.txt" contents:[overwrite copy]];

            expect([fileManager fileExistsAtPath:contentsPath isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir_prefix"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager contentsAtPath:contentsPath]).to.equal([overwrite copy]);
            expect([fileManager contentsAtPath:contentsPath.stringByDeletingLastPathComponent]).to.beNil();

            [fileManager createFileAtPath:@"dir_prefix/contents.txt" contents:[contents copy] attributes:nil];

            expect([fileManager fileExistsAtPath:contentsPath isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir_prefix"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager contentsAtPath:contentsPath]).to.equal([contents copy]);
            expect([fileManager contentsAtPath:contentsPath.stringByDeletingLastPathComponent]).to.beNil();
        });

        it(@"returns empty data for files with no explicitly set contents", ^{

            [fileManager setWorkingDirChildren:@"contents.txt", @"subdir/contents.txt", nil];
            NSData *empty = [NSData data];

            expect([fileManager contentsAtPath:[rootDir.path stringByAppendingPathComponent:@"contents.txt"]]).to.equal([empty copy]);
            expect([fileManager contentsAtPath:[rootDir.path stringByAppendingPathComponent:@"subdir/contents.txt"]]).to.equal([empty copy]);
        });

        it(@"returns nil for contents of directory", ^{

            [fileManager setWorkingDirChildren:@"subdir/", nil];

            expect([fileManager fileExistsAtPath:@"subdir" isDirectory:&isDir] && isDir).to.beTruthy();
            expect([fileManager contentsAtPath:[rootDir.path stringByAppendingPathComponent:@"subdir"]]).to.beNil();
            expect([fileManager contentsAtPath:[rootDir.path stringByAppendingPathComponent:@"subdir/"]]).to.beNil();
        });

        it(@"sets contents when creating file with base api", ^{

            NSString *contentsPath = [rootDir.path stringByAppendingPathComponent:@"contents.txt"];
            NSData *contents = [@"ABC123" dataUsingEncoding:NSUTF8StringEncoding];

            [fileManager createFileAtPath:contentsPath contents:contents attributes:nil];

            expect([fileManager contentsAtPath:contentsPath]).to.equal([contents copy]);
            expect([fileManager attributesOfItemAtPath:contentsPath error:NULL][NSFileType]).to.equal(NSFileTypeRegular);
        });
    });

    describe(@"removing files", ^{

        beforeEach(^{
            [fileManager setWorkingDirChildren:@"dir/", @"dir/file.txt", @"dir/dir/", @"dir/dir/file.txt", @"file.txt", nil];
        });

        it(@"removes a single file", ^{

            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"file.txt"]]).to.beTruthy();
            expect([fileManager removeItemAtPath:[rootDir.path stringByAppendingPathComponent:@"file.txt"] error:NULL]).to.beTruthy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"file.txt"]]).to.beFalsy();
        });

        it(@"removes a file from a subdirectory", ^{

            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beTruthy();
            expect([fileManager removeItemAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"] error:NULL]).to.beTruthy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
        });

        it(@"removes a directory and its descendants", ^{

            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir"]]).to.beTruthy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beTruthy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/dir"]]).to.beTruthy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/dir/file.txt"]]).to.beTruthy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"file.txt"]]).to.beTruthy();

            expect([fileManager removeItemAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/"] error:NULL]).to.beTruthy();

            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/"]]).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/dir"]]).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/dir/file.txt"]]).to.beFalsy();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"file.txt"]]).to.beTruthy();
        });

        it(@"removes the file contents", ^{

            expect([fileManager contentsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.equal([NSData data]);
            expect([fileManager removeItemAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"] error:NULL]).to.beTruthy();
            expect([fileManager contentsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beNil();
            expect([fileManager fileExistsAtPath:[rootDir.path stringByAppendingPathComponent:@"dir/file.txt"]]).to.beFalsy();
        });

    });

    describe(@"moving files", ^{

        it(@"moves a file", ^{

            __block NSError *error;
            NSString *source = [rootDir.path stringByAppendingPathComponent:@"move_src.txt"];
            NSString *dest = [rootDir.path stringByAppendingPathComponent:@"move_dest.txt"];
            NSData *contents = [@"MOVED FILE" dataUsingEncoding:NSUTF8StringEncoding];
            [fileManager createFileAtPath:source contents:contents attributes:nil];

            expect([fileManager moveItemAtPath:source toPath:dest error:&error]).to.beTruthy();
            expect([fileManager fileExistsAtPath:source isDirectory:&isDir]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:dest isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect(error).to.beNil();
        });

        it(@"moves directory and its contents", ^{

            __block NSError *error;
            NSString *source = [rootDir.path stringByAppendingPathComponent:@"src_base"];
            NSString *dest = [rootDir.path stringByAppendingPathComponent:@"dest_base"];
            [fileManager setWorkingDirChildren:
                @"src_base/",
                @"src_base/child1.txt",
                @"src_base/child2/",
                @"src_base/child2/grandchild.txt",
                nil];

            NSData *child1Contents = [@"child1" dataUsingEncoding:NSUTF8StringEncoding];
            [fileManager createFileAtPath:@"src_base/child1.txt" contents:child1Contents attributes:nil];
            NSData *grandchildContents = [@"grandchild" dataUsingEncoding:NSUTF8StringEncoding];
            [fileManager createFileAtPath:@"src_base/child2/grandchild.txt" contents:grandchildContents attributes:nil];

            expect([fileManager fileExistsAtPath:source isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"child1.txt"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"child2/"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"child2/grandchild.txt"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();

            expect([fileManager moveItemAtPath:source toPath:dest error:&error]).to.beTruthy();

            expect([fileManager fileExistsAtPath:dest isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager fileExistsAtPath:[dest stringByAppendingPathComponent:@"child1.txt"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager contentsAtPath:[dest stringByAppendingPathComponent:@"child1.txt"]]).to.equal(child1Contents);

            expect([fileManager fileExistsAtPath:[dest stringByAppendingPathComponent:@"child2/"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beTruthy();
            expect([fileManager fileExistsAtPath:[dest stringByAppendingPathComponent:@"child2/grandchild.txt"] isDirectory:&isDir]).to.beTruthy();
            expect(isDir).to.beFalsy();
            expect([fileManager contentsAtPath:[dest stringByAppendingPathComponent:@"child2/grandchild.txt"]]).to.equal(grandchildContents);

            expect([fileManager fileExistsAtPath:source isDirectory:&isDir]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"chi1d1.txt"] isDirectory:&isDir]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager contentsAtPath:[source stringByAppendingPathComponent:@"child1.txt"]]).to.beNil();

            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"chi1d2/"] isDirectory:&isDir]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager fileExistsAtPath:[source stringByAppendingPathComponent:@"chi1d2/grandchild.txt"] isDirectory:&isDir]).to.beFalsy();
            expect(isDir).to.beFalsy();
            expect([fileManager contentsAtPath:[source stringByAppendingPathComponent:@"chi1d2/grandchild.txt"]]).to.beNil();
        });

    });

});


SpecEnd
