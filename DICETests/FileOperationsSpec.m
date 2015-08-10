//
//  FileOperationsSpec.m
//  DICE
//
//  Created by Robert St. John on 8/4/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>
#import <OCMock/OCMock.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#import "FileOperations.h"


SpecBegin(FileOperations)

NSFileManager *fileManager = OCMClassMock([NSFileManager class]);

describe(@"MkdirOperation", ^{
    
    beforeAll(^{

    });
    
    beforeEach(^{

    });

    it(@"is not ready until dir url is set", ^{
        MkdirOperation *op = [[MkdirOperation alloc] init];

        id observer = observer = OCMClassMock([NSObject class]);
        OCMExpect([observer observeValueForKeyPath:@"isReady" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);

        [op addObserver:observer forKeyPath:@"isReady" options:0 context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.dirUrl).to.beNil;

        op.dirUrl = [NSURL URLWithString:@"/reports_dir"];

        expect(op.ready).to.equal(YES);
        OCMVerifyAll(observer);
    });

    it(@"has enough kvo tests", ^{
        failure(@"add more tests for prior options and different value cases");
    });

    it(@"is not ready until dependencies are finished", ^{
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:[NSURL URLWithString:@"/tmp/test/"] fileManager:fileManager];
        NSOperation *holdup = [[NSOperation alloc] init];
        [op addDependency:holdup];

        expect(op.ready).to.equal(NO);

        [holdup start];

        waitUntil(^(DoneCallback done) {
            if (holdup.finished) {
                done();
            }
        });

        expect(op.ready).to.equal(YES);
    });

    it(@"throws an exception when dest dir change is attempted while executing", ^{
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:[NSURL URLWithString:@"/tmp/test"] fileManager:fileManager];
        MkdirOperation *mockOp = OCMPartialMock(op);
        OCMStub([mockOp isExecuting]).andReturn(YES);

        expect(^{
            op.dirUrl = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.dirUrl.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change dirUrl after MkdirOperation has started");
        
        expect(op.dirUrl).to.equal([NSURL URLWithString:@"/tmp/test"]);
    });

    it(@"indicates when the directory was created", ^{
        NSURL *dir = [NSURL URLWithString:@"/tmp/dir"];
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:dir fileManager:fileManager];

        OCMExpect([fileManager fileExistsAtPath:dir.path isDirectory:[OCMArg anyPointer]]).andReturn(NO);
        OCMExpect([fileManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]).andReturn(YES);

        [op start];

        expect(op.dirWasCreated).to.equal(YES);
        expect(op.dirExisted).to.equal(NO);

        OCMVerifyAll((id)fileManager);
    });

    it(@"indicates when the directory already exists", ^{
        NSURL *dir = [NSURL URLWithString:@"/tmp/dir"];
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:dir fileManager:fileManager];

        BOOL isDir = YES;
        OCMExpect([fileManager fileExistsAtPath:dir.path isDirectory:[OCMArg setToValue:[NSValue valueWithPointer:&isDir]]]).andReturn(YES);

        [op start];

        expect(op.dirWasCreated).to.equal(NO);
        expect(op.dirExisted).to.equal(YES);

        OCMVerifyAll((id)fileManager);
    });

    it(@"indicates when the directory cannot be created", ^{
        NSURL *dir = [NSURL URLWithString:@"/tmp/dir"];
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:dir fileManager:fileManager];

        OCMExpect([fileManager fileExistsAtPath:dir.path isDirectory:[OCMArg anyPointer]]).andReturn(NO);
        OCMExpect([fileManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil]).andReturn(NO);

        [op start];

        expect(op.dirWasCreated).to.equal(NO);
        expect(op.dirExisted).to.equal(NO);

        OCMVerifyAll((id)fileManager);
    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});


describe(@"DeleteFileOperation", ^{

});

SpecEnd
