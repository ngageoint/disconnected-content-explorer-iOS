//
//  ExplodedHtmlImportProcessSpec.m
//  DICE
//
//  Created by Robert St. John on 8/3/16.
//  Copyright 2016 mil.nga. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "ImportProcess+Internal.h"
#import "ExplodedHtmlImportProcess.h"
#import "ParseJsonOperation.h"
#import "TestParseJsonOperation.h"
#import "KVOBlockObserver.h"


SpecBegin(ExplodedHtmlImportProcess)

describe(@"ExplodedHtmlImportProcess", ^{

    NSURL * const reportsDir = [NSURL fileURLWithPath:@"/dice/reports" isDirectory:YES];

    __block Report *report;

    beforeAll(^{

    });

    beforeEach(^{
        report = [[Report alloc] init];
    });

    it(@"updates the report url to the index page on the main thread", ^{

        NSURL *baseDirUrl = [reportsDir URLByAppendingPathComponent:@"ehip_spec" isDirectory:YES];
        NSURL *indexUrl = [baseDirUrl URLByAppendingPathComponent:@"index.html"];
        report.url = baseDirUrl;
        ExplodedHtmlImportProcess *import = [[ExplodedHtmlImportProcess alloc] initWithReport:report];
        KVOBlockObserver *observer = [[KVOBlockObserver alloc] initWithBlock:nil];
        [observer observeKeyPath:@"url" ofObject:report inContext:NULL options:NSKeyValueObservingOptionNew];

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperations:import.steps waitUntilFinished:NO];

        assertWithTimeout(1.0, thatEventually(@(import.isFinished)), isTrue());

        expect(observer.observations.count).to.equal(1);

        KVOObservation *observation = observer.observations.firstObject;
        expect(observation.wasMainThread).to.equal(YES);
        expect(observation.newValue).to.equal(indexUrl);
        expect(report.url).to.equal(indexUrl);
    });

    afterEach(^{

    });

    afterAll(^{

    });
});

SpecEnd
