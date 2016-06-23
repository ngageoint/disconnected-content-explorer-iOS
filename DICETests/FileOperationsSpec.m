//
//  FileOperationsSpec.m
//  DICE
//
//  Created by Robert St. John on 8/4/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#define MOCKITO_SHORTHAND
#import <OCMockito/OCMockito.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#import "FileOperations.h"
#import "NSOperation+Blockable.h"


SpecBegin(FileOperations)


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
        expect(op.dirUrl).to.beNil;

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


describe(@"DeleteFileOperation", ^{

    __block NSFileManager *fileManager;

    beforeAll(^{
    });

    beforeEach(^{
        fileManager = mock([NSFileManager class]);
    });

    afterEach(^{
        stopMocking(fileManager);
    });

    it(@"deletes the file", ^{
        NSURL *doomed = [NSURL URLWithString:@"file:///var/dice/foo.txt"];
        DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:doomed fileManager:fileManager];

        [[given([fileManager removeItemAtURL:doomed error:NULL]) withMatcher:anything() forArgument:1] willReturnBool:YES];

        [op start];

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());

        [verify(fileManager) removeItemAtURL:doomed error:NULL];
        expect(op.fileWasDeleted).to.equal(YES);
    });

    it(@"inidicates the file was not deleted", ^{
        NSURL *doomed = [NSURL URLWithString:@"file:///var/dice/foo.txt"];
        DeleteFileOperation *op = [[DeleteFileOperation alloc] initWithFileUrl:doomed fileManager:fileManager];

        [[given([fileManager removeItemAtURL:doomed error:NULL]) withMatcher:anything() forArgument:1] willReturnBool:NO];

        [op start];

        assertWithTimeout(1.0, thatEventually(@(op.isFinished)), isTrue());

        [verify(fileManager) removeItemAtURL:doomed error:NULL];
        expect(op.fileWasDeleted).to.equal(NO);
    });

});

SpecEnd
