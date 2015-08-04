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

describe(@"MkdirOperation", ^{
    
    beforeAll(^{

    });
    
    beforeEach(^{

    });

    it(@"is not ready until dir url is set", ^{
        MkdirOperation *op = [[MkdirOperation alloc] init];

        id observer = observer = OCMClassMock([NSObject class]);
        OCMExpect([observer observeValueForKeyPath:@"ready" ofObject:op change:instanceOf([NSDictionary class]) context:NULL]);

        [op addObserver:observer forKeyPath:@"ready" options:0 context:NULL];

        expect(op.ready).to.equal(NO);
        expect(op.dirUrl).to.beNil;

        op.dirUrl = [NSURL URLWithString:@"/reports_dir"];

        expect(op.ready).to.equal(YES);
        OCMVerifyAll(observer);
    });

    it(@"is not ready until dependencies are finished", ^{
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:[NSURL URLWithString:@"/tmp/test/"]];
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
        MkdirOperation *op = [[MkdirOperation alloc] initWithDirUrl:[NSURL URLWithString:@"/tmp/test"]];
        MkdirOperation *mockOp = OCMPartialMock(op);
        OCMStub([mockOp isExecuting]).andReturn(YES);

        expect(^{
            op.dirUrl = [NSURL URLWithString:[NSString stringWithFormat:@"/var/%@", op.dirUrl.path]];
        }).to.raiseWithReason(@"IllegalStateException", @"cannot change dirUrl after MkdirOperation has started");
        
        expect(op.dirUrl).to.equal([NSURL URLWithString:@"/tmp/test"]);
    });

    it(@"makes a directory", ^{
        failure(@"unimplemented");
    });

    it(@"indicates when the directory already exists", ^{
        failure(@"unimplemented");
    });

    it(@"indicates when the directory cannot be created", ^{
        failure(@"unimplemented");
    });
    
    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
