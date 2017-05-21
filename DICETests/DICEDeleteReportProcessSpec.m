//
//  DICEDeleteReportProcessSpec.m
//  DICE
//
//  Created by Robert St. John on 5/16/17.
//  Copyright 2017 mil.nga. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "DICEDeleteReportProcess.h"
#import "Report.h"
#import "FileOperations.h"
#import "NSString+PathUtils.h"
#import "TestFileManager.h"


SpecBegin(DICEDeleteReportProcess)

describe(@"DICEDeleteReportProcess", ^{

    __block NSURL *reportsDir;
    __block NSURL *trashDir;
    __block TestFileManager *fileManager;

    beforeAll(^{

    });

    beforeEach(^{
        reportsDir = [NSURL fileURLWithPath:@"/dice" isDirectory:YES];
        trashDir = [reportsDir URLByAppendingPathComponent:@"trash" isDirectory:YES];
        fileManager = [[TestFileManager alloc] init];
        fileManager.rootDir = reportsDir;
        [fileManager createDirectoryAtURL:trashDir withIntermediateDirectories:YES attributes:nil error:NULL];
    });

    afterEach(^{

    });

    afterAll(^{
        
    });

    it(@"creates a unique dir in the trash dir to move the deleted files", ^{

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];
        [fileManager createFileAtPath:report.sourceFile.path contents:nil attributes:nil];
        [fileManager createDirectoryAtPath:report.importDir.path withIntermediateDirectories:YES attributes:nil error:NULL];
        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];
        NSURL *trashContainerDir = del.trashContainerDir;
        NSString *containerName = trashContainerDir.lastPathComponent;
        NSUUID *parsedDirName = [[NSUUID alloc] initWithUUIDString:containerName];
        MkdirOperation *mkdir = (MkdirOperation *) del.steps[0];

        expect([trashContainerDir.path descendsFromPath:trashDir.path]).to.beTruthy();
        expect(parsedDirName).toNot.beNil();
        expect(mkdir.dirUrl).to.equal(trashContainerDir);
    });

    it(@"moves the source file and import dir to the trash dir", ^{

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];

        [fileManager createFileAtPath:report.sourceFile.path contents:nil attributes:nil];
        [fileManager createDirectoryAtPath:report.importDir.path withIntermediateDirectories:YES attributes:nil error:NULL];

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];
        MkdirOperation *mkdir = (MkdirOperation *) del.steps[0];
        MoveFileOperation *mv1 = (MoveFileOperation *) del.steps[1];
        MoveFileOperation *mv2 = (MoveFileOperation *) del.steps[2];

        expect(mv1.sourceUrl).to.equal(report.importDir);
        expect(mv1.destUrl).to.equal([del.trashContainerDir URLByAppendingPathComponent:report.importDir.lastPathComponent isDirectory:YES]);
        expect(mv1.dependencies).to.contain(mkdir);
        expect(mv2.sourceUrl).to.equal(report.sourceFile);
        expect(mv2.destUrl).to.equal([del.trashContainerDir URLByAppendingPathComponent:report.sourceFile.lastPathComponent isDirectory:NO]);
        expect(mv2.dependencies).to.contain(mkdir);
    });

    it(@"does not move the source file if it does not exist", ^{

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];

        [fileManager createDirectoryAtURL:report.importDir withIntermediateDirectories:YES attributes:nil error:NULL];

        BOOL isDir = NO;
        expect([fileManager fileExistsAtPath:report.importDir.path isDirectory:(BOOL *)&isDir] && isDir).to.beTruthy();
        expect([fileManager fileExistsAtPath:report.sourceFile.path isDirectory:(BOOL *)&isDir] || isDir).to.beFalsy();

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];

        MkdirOperation *mkdir = (MkdirOperation *)del.steps[0];
        MoveFileOperation *mv = (MoveFileOperation *)del.steps[1];
        DeleteFileOperation *rm = (DeleteFileOperation *)del.steps[2];
        NSURL *trashContainer = mkdir.dirUrl;

        expect(mv.dependencies).to.contain(mkdir);
        expect(mv.sourceUrl).to.equal(report.importDir);
        expect(mv.destUrl).to.equal([trashContainer URLByAppendingPathComponent:report.importDir.lastPathComponent isDirectory:YES]);
        expect(rm.dependencies).to.haveCountOf(1);
        expect(rm.dependencies).to.contain(mv);
    });

    it(@"does not move the import dir if it does not exist", ^{

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];

        [fileManager createFileAtPath:report.sourceFile.path contents:nil attributes:nil];

        BOOL isDir = NO;
        expect([fileManager fileExistsAtPath:report.importDir.path isDirectory:(BOOL *)&isDir] || isDir).to.beFalsy();
        expect([fileManager fileExistsAtPath:report.sourceFile.path isDirectory:(BOOL *)&isDir] && !isDir).to.beTruthy();

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];

        MkdirOperation *mkdir = (MkdirOperation *)del.steps[0];
        MoveFileOperation *mv = (MoveFileOperation *)del.steps[1];
        DeleteFileOperation *rm = (DeleteFileOperation *)del.steps[2];
        NSURL *trashContainer = mkdir.dirUrl;

        expect(mv.dependencies).to.contain(mkdir);
        expect(mv.sourceUrl).to.equal(report.sourceFile);
        expect(mv.destUrl).to.equal([trashContainer URLByAppendingPathComponent:report.sourceFile.lastPathComponent]);
        expect(rm.dependencies).to.haveCountOf(1);
        expect(rm.dependencies).to.contain(mv);
    });

    it(@"does not move the source file if it is nil", ^{

        Report *report = [[Report alloc] init];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];

        [fileManager createDirectoryAtURL:report.importDir withIntermediateDirectories:YES attributes:nil error:NULL];

        BOOL isDir = NO;
        expect([fileManager fileExistsAtPath:report.importDir.path isDirectory:(BOOL *)&isDir] && isDir).to.beTruthy();
        expect(report.sourceFile).to.beNil();

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];

        MkdirOperation *mkdir = (MkdirOperation *)del.steps[0];
        MoveFileOperation *mv = (MoveFileOperation *)del.steps[1];
        DeleteFileOperation *rm = (DeleteFileOperation *)del.steps[2];
        NSURL *trashContainer = mkdir.dirUrl;

        expect(mv.dependencies).to.contain(mkdir);
        expect(mv.sourceUrl).to.equal(report.importDir);
        expect(mv.destUrl).to.equal([trashContainer URLByAppendingPathComponent:report.importDir.lastPathComponent isDirectory:YES]);
        expect(rm.dependencies).to.haveCountOf(1);
        expect(rm.dependencies).to.contain(mv);
    });

    it(@"does not move the import dir if it is nil", ^{

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];

        [fileManager createFileAtPath:report.sourceFile.path contents:nil attributes:nil];

        BOOL isDir = NO;
        expect(report.importDir).to.beNil();
        expect([fileManager fileExistsAtPath:report.sourceFile.path isDirectory:(BOOL *)&isDir] && !isDir).to.beTruthy();

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];

        MkdirOperation *mkdir = (MkdirOperation *)del.steps[0];
        MoveFileOperation *mv = (MoveFileOperation *)del.steps[1];
        DeleteFileOperation *rm = (DeleteFileOperation *)del.steps[2];
        NSURL *trashContainer = mkdir.dirUrl;

        expect(mv.dependencies).to.contain(mkdir);
        expect(mv.sourceUrl).to.equal(report.sourceFile);
        expect(mv.destUrl).to.equal([trashContainer URLByAppendingPathComponent:report.sourceFile.lastPathComponent]);
        expect(rm.dependencies).to.haveCountOf(1);
        expect(rm.dependencies).to.contain(mv);
    });

    it(@"does not delete the trash files until all files have moved to the trash dir", ^{

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];

        [fileManager createFileAtPath:report.sourceFile.path contents:nil attributes:nil];
        [fileManager createDirectoryAtPath:report.importDir.path withIntermediateDirectories:YES attributes:nil error:NULL];

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];
        MkdirOperation *mkdir = (MkdirOperation *) del.steps[0];
        MoveFileOperation *mv1 = (MoveFileOperation *) del.steps[1];
        MoveFileOperation *mv2 = (MoveFileOperation *) del.steps[2];
        DeleteFileOperation *rm = (DeleteFileOperation *) del.steps[3];

        expect(rm.dependencies).to.haveCountOf(2);
        expect(rm.dependencies).to.contain(mv1);
        expect(rm.dependencies).to.contain(mv2);
        expect(rm.fileUrl).to.beNil();

        [mkdir start];

        expect(mkdir.isFinished).to.beTruthy();
        expect(mv1.isReady).to.beTruthy();

        [mv1 start];

        expect(mv1.isFinished).to.beTruthy();
        expect(rm.fileUrl).to.beNil();
        expect(rm.isReady).to.beFalsy();

        [mv2 start];

        expect(mv2.isFinished).to.beTruthy();
        expect(rm.fileUrl).to.equal(mkdir.dirUrl);
        expect(rm.isReady).to.beTruthy();
    });

    it(@"does not delete the trash files until all files have moved to the trash dir regardless of move order", ^{

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];

        [fileManager createFileAtPath:report.sourceFile.path contents:nil attributes:nil];
        [fileManager createDirectoryAtPath:report.importDir.path withIntermediateDirectories:YES attributes:nil error:NULL];

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];
        MkdirOperation *mkdir = (MkdirOperation *) del.steps[0];
        MoveFileOperation *mv1 = (MoveFileOperation *) del.steps[1];
        MoveFileOperation *mv2 = (MoveFileOperation *) del.steps[2];
        DeleteFileOperation *rm = (DeleteFileOperation *) del.steps[3];

        expect(rm.dependencies).to.haveCountOf(2);
        expect(rm.dependencies).to.contain(mv1);
        expect(rm.dependencies).to.contain(mv2);
        expect(rm.fileUrl).to.beNil();

        [mkdir start];

        expect(mkdir.isFinished).to.beTruthy();
        expect(mv1.isReady).to.beTruthy();

        [mv2 start];

        expect(mv2.isFinished).to.beTruthy();
        expect(rm.fileUrl).to.beNil();
        expect(rm.isReady).to.beFalsy();

        [mv1 start];

        expect(mv1.isFinished).to.beTruthy();
        expect(rm.fileUrl).to.equal(mkdir.dirUrl);
        expect(rm.isReady).to.beTruthy();
    });

    it(@"notifies the delegate after the files moved to the trash", ^{

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];

        [fileManager createFileAtPath:report.sourceFile.path contents:nil attributes:nil];
        [fileManager createDirectoryAtPath:report.importDir.path withIntermediateDirectories:YES attributes:nil error:NULL];

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];
        MoveFileOperation *mv1 = (MoveFileOperation *) del.steps[1];
        MoveFileOperation *mv2 = (MoveFileOperation *) del.steps[2];
        DeleteFileOperation *rm = (DeleteFileOperation *) del.steps[3];

        id<DICEDeleteReportProcessDelegate> delegate = mockProtocol(@protocol(DICEDeleteReportProcessDelegate));
        [givenVoid([delegate filesDidMoveToTrashByDeleteReportProcess:del]) willDo:^id _Nonnull(NSInvocation * _Nonnull invoc) {
            expect(rm.fileUrl).to.beNil();
            expect(rm.isReady).to.beFalsy();
            return nil;
        }];
        del.delegate = delegate;

        [ops addOperations:del.steps waitUntilFinished:YES];

        [verify(delegate) filesDidMoveToTrashByDeleteReportProcess:del];
    });

    it(@"notifies the delegate after the source file moved to the trash", ^{

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        [fileManager createFileAtPath:report.sourceFile.path contents:nil attributes:nil];

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];
        DeleteFileOperation *rm = (DeleteFileOperation *) del.steps[2];

        id<DICEDeleteReportProcessDelegate> delegate = mockProtocol(@protocol(DICEDeleteReportProcessDelegate));
        [givenVoid([delegate filesDidMoveToTrashByDeleteReportProcess:del]) willDo:^id _Nonnull(NSInvocation * _Nonnull invoc) {
            expect(rm.fileUrl).to.beNil();
            expect(rm.isReady).to.beFalsy();
            return nil;
        }];
        del.delegate = delegate;

        [ops addOperations:del.steps waitUntilFinished:YES];

        [verify(delegate) filesDidMoveToTrashByDeleteReportProcess:del];
    });

    it(@"notifies the delegate after the import dir moved to the trash", ^{

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];

        Report *report = [[Report alloc] init];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];
        [fileManager createDirectoryAtPath:report.importDir.path withIntermediateDirectories:YES attributes:nil error:NULL];

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];
        DeleteFileOperation *rm = (DeleteFileOperation *) del.steps[2];

        id<DICEDeleteReportProcessDelegate> delegate = mockProtocol(@protocol(DICEDeleteReportProcessDelegate));
        [givenVoid([delegate filesDidMoveToTrashByDeleteReportProcess:del]) willDo:^id _Nonnull(NSInvocation * _Nonnull invoc) {
            expect(rm.fileUrl).to.beNil();
            expect(rm.isReady).to.beFalsy();
            return nil;
        }];
        del.delegate = delegate;

        [ops addOperations:del.steps waitUntilFinished:YES];

        [verify(delegate) filesDidMoveToTrashByDeleteReportProcess:del];
    });

    it(@"notifies the delegate if their are no files to delete", ^{

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];

        Report *report = [[Report alloc] init];
        report.sourceFile = [NSURL fileURLWithPath:@"/dice/reports/source.zip"];
        report.importDir = [NSURL fileURLWithPath:@"/dice/reports/source.zip.imported" isDirectory:YES];

        DICEDeleteReportProcess *del = [[DICEDeleteReportProcess alloc] initWithReport:report trashDir:trashDir fileManager:fileManager];

        id<DICEDeleteReportProcessDelegate> delegate = mockProtocol(@protocol(DICEDeleteReportProcessDelegate));
        del.delegate = delegate;

        [ops addOperations:del.steps waitUntilFinished:YES];

        [verify(delegate) noFilesFoundToDeleteByDeleteReportProcess:del];
    });
});

SpecEnd
