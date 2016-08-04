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

#import "ExplodedHtmlImportProcess.h"
#import "ParseJsonOperation.h"


SpecBegin(ExplodedHtmlImportProcess)

describe(@"ExplodedHtmlImportProcess", ^{

    NSURL * const reportsDir = [NSURL fileURLWithPath:@"/dice/reports" isDirectory:YES];

    __block NSFileManager *fileManager;

    beforeAll(^{

    });

    beforeEach(^{

    });

    it(@"parses the report descriptor from the standard location under the base dir", ^{
        Report *report = [[Report alloc] init];
        NSString *reportPath = [reportsDir.path stringByAppendingPathComponent:@"test_report"];
        report.url = [NSURL fileURLWithPath:reportPath isDirectory:YES];
        ExplodedHtmlImportProcess *import = [[ExplodedHtmlImportProcess alloc] initWithReport:report fileManager:fileManager];
        ParseJsonOperation *op = (ParseJsonOperation *) import.steps.firstObject;
        NSString *descriptorPath = [reportPath stringByAppendingPathComponent:@"metadata.json"];
        NSURL *descriptorUrl = [NSURL fileURLWithPath:descriptorPath isDirectory:NO];

        expect(op.jsonUrl).to.equal(descriptorUrl);
    });

    afterEach(^{

    });

    afterAll(^{

    });
});

SpecEnd
