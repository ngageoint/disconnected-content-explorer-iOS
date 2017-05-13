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

describe(@"ReportStore_FileManager", ^{

    __block TestFileManager *fileManager;
    __block NSURL *reportsDir;

    beforeEach(^{
        fileManager = [[TestFileManager alloc] init];
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

SpecEnd
