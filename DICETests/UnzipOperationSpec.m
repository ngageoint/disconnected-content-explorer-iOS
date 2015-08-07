//
//  UnzipOperationSpec.m
//  DICE
//
//  Created by Robert St. John on 7/31/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#define HC_SHORTHAND
#import <OCHamcrest/OCHamcrest.h>

#import <OCMock/OCMock.h>

#import "UnzipOperation.h"


SpecBegin(UnzipOperation)

describe(@"UnzipOperation", ^{

    beforeAll(^{

    });
    
    beforeEach(^{

    });

    it(@"it throws an exception if zip file is nil", ^{
        __block UnzipOperation *op;

        expect(^{
            op = [[UnzipOperation alloc] initWithZipFile:nil destDir:[NSURL URLWithString:@"/some/dir"]];
        }).to.raiseWithReason(@"IllegalArgumentException", @"zipFile is nil");

        expect(op).to.beNil;
    });

    it(@"is not ready until dest dir is set", ^{
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:OCMClassMock([ZipFile class]) destDir:nil];

        id observer = observer = OCMClassMock([NSObject class]);
        OCMExpect([observer observeValueForKeyPath:@"ready" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);

        [op addObserver:observer forKeyPath:@"ready" options:0 context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.destDir).to.beNil;

        op.destDir = [NSURL URLWithString:@"/reports_dir"];

        expect(op.ready).to.equal(YES);
        OCMVerifyAll(observer);
    });

    it(@"is not ready until dependencies are finished", ^{
        ZipFile *zipFile = OCMClassMock([ZipFile class]);
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:zipFile destDir:[NSURL URLWithString:@"/some/dir"]];
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
        UnzipOperation *op = [[UnzipOperation alloc] initWithZipFile:OCMClassMock([ZipFile class]) destDir:[NSURL URLWithString:@"/tmp/"]];
        UnzipOperation *mockOp = OCMPartialMock(op);
        OCMStub([mockOp isExecuting]).andReturn(YES);

        expect(^{
            op.destDir = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.destDir.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change destDir after UnzipOperation has started");

        expect(op.destDir).to.equal([NSURL URLWithString:@"/tmp/"]);
    });

    it(@"reports unzip progress", ^{
        failure(@"unimplemented");
    });

    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
