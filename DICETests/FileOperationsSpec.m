//
//  FileOperationsSpec.m
//  DICE
//
//  Created by Robert St. John on 8/4/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCMockito/OCMockito.h>
#import <OCHamcrest/OCHamcrest.h>

#import "FileOperations.h"
#import "NSOperation+Blockable.h"
#import "KVOBlockObserver.h"


SpecBegin(FileOperations)

describe(@"NSFileManager behavior", ^{

    it(@"does something when moving a file that does not exist", ^{
        NSURL *source = [NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/%@", [NSUUID UUID].UUIDString]];
        NSURL *dest = [NSURL fileURLWithPath:@"/tmp/who_cares"];
        NSError *err;
        BOOL moved = [NSFileManager.defaultManager moveItemAtURL:source toURL:dest error:&err];

        expect(moved).to.beFalsy();
        expect(err).toNot.beNil();
    });

});

describe(@"MkdirOperation", ^{

    __block NSFileManager *fileManager;
    
    beforeAll(^{
    });

    beforeEach(^{
        fileManager = mock([NSFileManager class]);
    });

    it(@"is not ready until dir url is set", ^{
        MkdirOperation *op = [[MkdirOperation alloc] init];

        id observer = mock([NSObject class]);

        [op addObserver:observer forKeyPath:@"isReady" options:NSKeyValueObservingOptionPrior context:NULL];
        [op addObserver:observer forKeyPath:@"dirUrl" options:NSKeyValueObservingOptionPrior context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.dirUrl).to.beNil();

        op.dirUrl = [NSURL URLWithString:@"/reports_dir"];

        expect(op.ready).to.equal(YES);

        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL];
        [verify(observer) observeValueForKeyPath:@"dirUrl" ofObject:op change:hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES) context:NULL];
        [verify(observer) observeValueForKeyPath:@"dirUrl" ofObject:op change:isNot(hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES)) context:NULL];
        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:isNot(hasEntry(NSKeyValueChangeNotificationIsPriorKey, @YES)) context:NULL];
    });

    it(@"is not ready until dependencies are finished", ^{
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:[NSURL URLWithString:@"/tmp/test/"] fileManager:fileManager];
        NSOperation *holdup = [[NSOperation alloc] init];
        [op addDependency:holdup];

        expect(op.ready).to.equal(NO);

        [holdup start];

        assertWithTimeout(1.0, thatEventually(@(op.isReady)), isTrue());
    });

    it(@"is ready if cancelled before executing", ^{
        MkdirOperation *op = [[MkdirOperation alloc] init];
        id observer = mock([NSObject class]);
        [op addObserver:observer forKeyPath:@"isReady" options:0 context:NULL];

        expect(op.isReady).to.equal(NO);

        [op cancel];

        expect(op.isReady).to.equal(YES);
        [verify(observer) observeValueForKeyPath:@"isReady" ofObject:op change:anything() context:NULL];
    });

    it(@"throws an exception when dest dir change is attempted while executing", ^{
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:[NSURL URLWithString:@"/tmp/test"] fileManager:fileManager];
        [op block];

        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        [queue addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        expect(^{
            op.dirUrl = [NSURL URLWithString:[NSString stringWithFormat:@"/var%@", op.dirUrl.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change dirUrl after MkdirOperation has started");
        
        expect(op.dirUrl).to.equal([NSURL URLWithString:@"/tmp/test"]);

        [op unblock];

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());
    });

    it(@"indicates when the directory was created", ^{
        NSURL *dir = [NSURL URLWithString:@"/tmp/dir"];
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:dir fileManager:fileManager];

        [[given([fileManager fileExistsAtPath:dir.path isDirectory:NULL]) withMatcher:anything() forArgument:1] willReturn:@NO];
        [given([fileManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]) willReturn:@YES];

        [op start];

        expect(op.dirWasCreated).to.equal(YES);
        expect(op.dirExisted).to.equal(NO);
    });

    it(@"indicates when the directory already exists", ^{
        NSURL *dir = [NSURL URLWithString:@"/tmp/dir"];
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:dir fileManager:fileManager];

        [[given([fileManager fileExistsAtPath:dir.path isDirectory:NULL]) withMatcher:anything() forArgument:1] willDo:^id(NSInvocation *invocation) {
            BOOL *arg = NULL;
            [invocation getArgument:&arg atIndex:3];
            *arg = YES;
            return @YES;
        }];

        [op start];

        expect(op.dirWasCreated).to.equal(NO);
        expect(op.dirExisted).to.equal(YES);

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());
    });

    it(@"indicates when the directory cannot be created", ^{
        NSURL *dir = [NSURL URLWithString:@"/tmp/dir"];
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:dir fileManager:fileManager];

        [[given([fileManager fileExistsAtPath:dir.path isDirectory:NULL]) withMatcher:anything() forArgument:1] willReturnBool:NO];
        [given([fileManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]) willReturnBool:NO];

        [op start];

        expect(op.dirWasCreated).to.equal(NO);
        expect(op.dirExisted).to.equal(NO);

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());
    });
    
    afterEach(^{
        stopMocking(fileManager);
    });

    afterAll(^{
    });
});

#define observeIsReadyOn(operation) [[[KVOBlockObserver alloc] initWithBlock:nil] observeKeyPath:@"isReady" ofObject:op inContext:NULL options:NSKeyValueObservingOptionPrior|NSKeyValueObservingOptionNew];

describe(@"MoveFileOperation", ^{

    __block NSFileManager *fileManager;
    __block NSURL *baseDir;
    __block NSURL *source;
    __block NSURL *dest;
    __block NSData *contents;

    beforeAll(^{
    });

    beforeEach(^{
        fileManager = [[NSFileManager alloc] init];
        NSURL *tmpDir = [fileManager temporaryDirectory];
        NSString *baseDirName = [NSUUID UUID].UUIDString;
        baseDir = [tmpDir URLByAppendingPathComponent:baseDirName];
        if (![fileManager createDirectoryAtURL:baseDir withIntermediateDirectories:YES attributes:nil error:NULL]) {
            [NSException raise:NSInternalInconsistencyException format:@"failed to base dir %@", baseDir];
        }
        NSString *sourceName = @"source.txt";
        NSString *destName = @"dest.txt";
        source = [baseDir URLByAppendingPathComponent:sourceName];
        dest = [baseDir URLByAppendingPathComponent:destName];
        contents = [baseDirName dataUsingEncoding:NSUTF8StringEncoding];
        if (![contents writeToURL:source atomically:YES]) {
            [NSException raise:NSInternalInconsistencyException format:@"failed to write contents to source file %@", source];
        }
    });

    afterEach(^{
        [fileManager removeItemAtURL:baseDir error:NULL];
    });

    afterAll(^{
    });

    it(@"is not ready until source and dest are set", ^{

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];

        expect(op.isReady).to.beTruthy();

        op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:nil fileManager:fileManager];
        KVOBlockObserver *obs = observeIsReadyOn(op);

        expect(op.isReady).to.beFalsy();
        expect(obs.observations).to.beEmpty();

        op.destUrl = dest;

        expect(op.isReady).to.beTruthy();
        expect(obs.observations).to.haveCountOf(2);
        expect(obs.observations[0].isPrior).to.beTruthy();
        expect(obs.observations[1].isPrior).to.beFalsy();

        [op removeObserver:obs forKeyPath:@"isReady"];

        op = [[MoveFileOperation alloc] initWithSourceUrl:nil destUrl:dest fileManager:fileManager];
        obs = observeIsReadyOn(op);

        expect(op.isReady).to.beFalsy();
        expect(obs.observations).to.beEmpty();

        op.sourceUrl = source;

        expect(op.isReady).to.beTruthy();
        expect(obs.observations).to.haveCountOf(2);
        expect(obs.observations[0].isPrior).to.beTruthy();
        expect(obs.observations[1].isPrior).to.beFalsy();

        [op removeObserver:obs forKeyPath:@"isReady"];

        op = [[MoveFileOperation alloc] initWithSourceUrl:nil destUrl:nil fileManager:fileManager];
        obs = observeIsReadyOn(op);

        expect(op.isReady).to.beFalsy();
        expect(obs.observations).to.beEmpty();

        op.sourceUrl = source;

        expect(op.isReady).to.beFalsy();
        expect(obs.observations).to.beEmpty();

        op.destUrl = dest;

        expect(obs.observations).to.haveCountOf(2);
        expect(obs.observations[0].isPrior).to.beTruthy();
        expect(obs.observations[1].isPrior).to.beFalsy();

        [op removeObserver:obs forKeyPath:@"isReady"];
    });

    it(@"does not generate kvo notifications when values are equal", ^{

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];
        KVOBlockObserver *obs = [[[[[KVOBlockObserver alloc] initWithBlock:nil]
            observeKeyPath:@"sourceUrl" ofObject:op inContext:NULL options:0]
            observeKeyPath:@"destUrl" ofObject:op inContext:NULL options:0]
            observeKeyPath:@"isReady" ofObject:op inContext:NULL options:0];

        op.sourceUrl = [NSURL fileURLWithPath:source.path];
        op.destUrl = [NSURL fileURLWithPath:dest.path];

        expect(obs.observations).to.beEmpty();
    });

    it(@"raises an exception when setting urls while executing", ^{

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];
        [op block];

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        expect(^{ op.sourceUrl = [NSURL fileURLWithPath:@"/new/source.txt"]; }).to.raise(NSInternalInconsistencyException);
        expect(^{ op.destUrl = [NSURL fileURLWithPath:@"/new/dest.txt"]; }).to.raise(NSInternalInconsistencyException);

        [op unblock];

        [ops waitUntilAllOperationsAreFinished];
    });

    it(@"raises an exception when setting urls after finished", ^{

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];

        [op start];

        expect(op.isFinished).to.beTruthy();
        expect(^{ op.sourceUrl = [NSURL fileURLWithPath:@"/new/source.txt"]; }).to.raise(NSInternalInconsistencyException);
        expect(^{ op.destUrl = [NSURL fileURLWithPath:@"/new/dest.txt"]; }).to.raise(NSInternalInconsistencyException);
    });

    it(@"moves the file", ^{

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];

        [op start];

        expect(op.fileWasMoved).to.beTruthy();
        expect([fileManager fileExistsAtPath:source.path]).to.beFalsy();
        expect([fileManager fileExistsAtPath:dest.path]).to.beTruthy();
        expect([fileManager contentsAtPath:dest.path]).to.equal(contents);
    });

    it(@"inidicates when the move was not successful", ^{

        fileManager = mock([NSFileManager class]);

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];

        [given([fileManager moveItemAtURL:anything() toURL:anything() error:NULL]) willReturnBool:NO];

        [op start];

        [[verify(fileManager) withMatcher:anything() forArgument:2] moveItemAtURL:source toURL:dest error:NULL];
        expect(op.fileWasMoved).to.beFalsy();
    });

    it(@"gets dequeued if cancelled before becoming ready", ^{

        fileManager = mock([NSFileManager class]);

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:nil destUrl:nil fileManager:fileManager];

        expect(op.isReady).to.beFalsy();

        [op cancel];

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperation:op];

        [ops waitUntilAllOperationsAreFinished];

        [[verifyCount(fileManager, never()) withMatcher:anything() forArgument:2] moveItemAtURL:anything() toURL:anything() error:NULL];
    });

    it(@"gets dequeued and does not move file if enqueued then cancelled before executing", ^{

        fileManager = mock([NSFileManager class]);

        MoveFileOperation *move = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];
        NSBlockOperation *cancelMove = [NSBlockOperation blockOperationWithBlock:^{
            [move cancel];
        }];
        [move addDependency:cancelMove];

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperations:@[cancelMove, move] waitUntilFinished:YES];

        [[verifyCount(fileManager, never()) withMatcher:anything() forArgument:2] moveItemAtURL:source toURL:dest error:NULL];
    });

    it(@"does not move the file if cancelled before executing", ^{

        fileManager = mock([NSFileManager class]);

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];

        [op cancel];
        [op start];

        [[verifyCount(fileManager, never()) withMatcher:anything() forArgument:2] moveItemAtURL:anything() toURL:anything() error:NULL];
    });

    it(@"sets the error when the source file does not exist", ^{

        expect([fileManager removeItemAtURL:source error:NULL]).to.beTruthy();

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];
        [op start];

        expect(op.fileWasMoved).to.beFalsy();
        expect(op.error).toNot.beNil();
        expect(op.error.code).to.equal(NSFileNoSuchFileError);
        expect(op.error.userInfo[NSFilePathErrorKey]).to.equal(source.path);
    });

    it(@"sets the error when the dest parent dir does not exist", ^{

        dest = [baseDir URLByAppendingPathComponent:@"another_dir/dest.txt"];

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];
        [op start];

        expect(op.fileWasMoved).to.beFalsy();
        expect(op.error).toNot.beNil();
        expect(op.error.code).to.equal(NSFileNoSuchFileError);
        expect([fileManager contentsAtPath:source.path]).to.equal(contents);
    });

    it(@"sets create dest dirs flag when explicitly set", ^{

        MoveFileOperation *op = [[[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager] createDestDirs:YES];

        expect(op.createDestDirs).to.beTruthy();

        op = [[[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager] createDestDirs:NO];

        expect(op.createDestDirs).to.beFalsy();

        [op createDestDirs:YES];

        expect(op.createDestDirs).to.beTruthy();

        [op createDestDirs:NO];

        expect(op.createDestDirs).to.beFalsy();
    });

    it(@"does not create dest dirs by default", ^{

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];

        expect(op.createDestDirs).to.beFalsy();
    });

    it(@"creates dest dirs when requested", ^{

        dest = [baseDir URLByAppendingPathComponent:@"another_dir/dest.txt"];

        MoveFileOperation *op = [[[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager] createDestDirs:YES];
        [op start];

        expect(op.fileWasMoved).to.beTruthy();
        expect(op.error).to.beNil();
        expect([fileManager contentsAtPath:dest.path]).to.equal(contents);
    });

    it(@"raises an exception if calling create dest dirs while executing", ^{

        MoveFileOperation *op = [[[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager] block];

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        expect(^{ [op createDestDirs:YES]; }).to.raise(NSInternalInconsistencyException);

        [op unblock];
        [ops waitUntilAllOperationsAreFinished];
    });

    it(@"raises an exception if calling create dest dirs after finished", ^{

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];
        [op start];

        expect(op.isFinished).to.beTruthy();
        expect(^{ [op createDestDirs:YES]; }).to.raise(NSInternalInconsistencyException);
    });

    it(@"does not attempt to move if create dest dirs fails", ^{

        fileManager = mock([NSFileManager class]);
        NSError *createDirErr = [[NSError alloc] initWithDomain:NSURLErrorDomain code:NSFileReadNoPermissionError userInfo:@{NSLocalizedDescriptionKey: @"test error"}];
        [[given([fileManager createDirectoryAtURL:anything() withIntermediateDirectories:YES attributes:anything() error:NULL]) withMatcher:anything() forArgument:3] willDo:^id _Nonnull(NSInvocation * _Nonnull invoc) {
            NSError * __autoreleasing *errOut = NULL;
            [invoc getArgument:&errOut atIndex:5];
            *errOut = createDirErr;
            return @NO;
        }];

        MoveFileOperation *op = [[[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager] createDestDirs:YES];
        [op start];

        expect(op.fileWasMoved).to.beFalsy();
        expect(op.error).to.beIdenticalTo(createDirErr);
        [[verifyCount(fileManager, never()) withMatcher:anything() forArgument:2] moveItemAtURL:anything() toURL:anything() error:NULL];
    });

    it(@"sets the dest url to dest dir with last path component of source url", ^{

        NSURL *destDir = [baseDir URLByAppendingPathComponent:@"dir1"];
        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destDirUrl:destDir fileManager:fileManager];

        expect(op.destUrl).to.equal([destDir URLByAppendingPathComponent:source.lastPathComponent]);

        [destDir URLByAppendingPathComponent:@"dir2"];
        [op setDestDirUrl:destDir];

        expect(op.destUrl).to.equal([destDir URLByAppendingPathComponent:source.lastPathComponent]);
    });

    it(@"raises an exception setting dest dir when op is executing or finished", ^{

        MoveFileOperation *op = [[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager];

        [op start];

        expect(op.isFinished).to.beTruthy();
        expect(^{ [op setDestDirUrl:[baseDir URLByAppendingPathComponent:@"another_dir"]]; }).to.raise(NSInternalInconsistencyException);

        op = [[[MoveFileOperation alloc] initWithSourceUrl:source destUrl:dest fileManager:fileManager] block];
        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        expect(^{ [op setDestDirUrl:[baseDir URLByAppendingPathComponent:@"another_dir"]]; }).to.raise(NSInternalInconsistencyException);

        [op unblock];
        [ops waitUntilAllOperationsAreFinished];
    });
});


describe(@"DeleteFileOperation", ^{

    __block NSFileManager *fileManager;
    __block NSURL *doomed;

    beforeAll(^{
    });

    beforeEach(^{
        fileManager = mock([NSFileManager class]);
        doomed = [NSURL fileURLWithPath:@"/delete/me.txt"];
    });

    afterEach(^{
        stopMocking(fileManager);
    });

    it(@"deletes the file", ^{

        DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:doomed fileManager:fileManager];

        [[given([fileManager removeItemAtURL:doomed error:NULL]) withMatcher:anything() forArgument:1] willReturnBool:YES];

        [op start];

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());

        [verify(fileManager) removeItemAtURL:doomed error:NULL];
        expect(op.fileWasDeleted).to.equal(YES);
    });

    it(@"inidicates the file was not deleted", ^{

        DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:doomed fileManager:fileManager];

        [[given([fileManager removeItemAtURL:doomed error:NULL]) withMatcher:anything() forArgument:1] willReturnBool:NO];

        [op start];

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());

        [verify(fileManager) removeItemAtURL:doomed error:NULL];
        expect(op.fileWasDeleted).to.equal(NO);
    });

    it(@"is not ready until the dir url is set", ^{

        DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:nil fileManager:fileManager];

        expect(op.isReady).to.beFalsy();

        op.fileUrl = doomed;

        expect(op.isReady).to.beTruthy();
    });

    it(@"raises an exception when setting the file url while executing", ^{

        DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:doomed fileManager:fileManager];
        [op block];

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperation:op];

        assertWithTimeout(1.0, thatEventually(@(op.isExecuting)), isTrue());

        expect(^{ op.fileUrl = [NSURL fileURLWithPath:@"/some/other.txt"]; }).to.raise(NSInternalInconsistencyException);

        [op unblock];

        [ops waitUntilAllOperationsAreFinished];
    });

    it(@"raises an exception when setting the file url after finished", ^{

        DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:doomed fileManager:fileManager];

        [op start];

        expect(op.isFinished).to.beTruthy();
        expect(^{ op.fileUrl = [NSURL fileURLWithPath:@"/some/other.txt"]; }).to.raise(NSInternalInconsistencyException);
    });

    describe(@"key-value observing", ^{

        it(@"notifies about fileUrl when the value changes", ^{

            DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:nil fileManager:fileManager];
            KVOBlockObserver *obs = [KVOBlockObserver recordObservationsOfKeyPath:@"fileUrl" ofObject:op options:NSKeyValueObservingOptionPrior];

            op.fileUrl = nil;

            expect(obs.observations).to.beEmpty();

            op.fileUrl = doomed;

            expect(obs.observations).to.haveCountOf(2);
            expect(obs.observations.firstObject.isPrior).to.beTruthy();

            op.fileUrl = doomed;

            expect(obs.observations).to.haveCountOf(2);

            op.fileUrl = [NSURL fileURLWithPath:doomed.path];

            expect(obs.observations).to.haveCountOf(2);
        });

        it(@"notifies about isReady when fileUrl is set", ^{

            DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:nil fileManager:fileManager];
            KVOBlockObserver *obs = [KVOBlockObserver recordObservationsOfKeyPath:@"isReady" ofObject:op options:NSKeyValueObservingOptionPrior];

            op.fileUrl = nil;

            expect(obs.observations).to.beEmpty();

            op.fileUrl = doomed;

            expect(obs.observations).to.haveCountOf(2);
            expect(obs.observations.firstObject.isPrior).to.beTruthy();

            op.fileUrl = doomed;

            expect(obs.observations).to.haveCountOf(2);

            op.fileUrl = [NSURL fileURLWithPath:doomed.path];
            
            expect(obs.observations).to.haveCountOf(2);
        });

    });

});

SpecEnd
