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
        report.url = [reportsDir URLByAppendingPathComponent:@"test_report" isDirectory:YES];
        ExplodedHtmlImportProcess *import = [[ExplodedHtmlImportProcess alloc] initWithReport:report fileManager:fileManager];
        ParseJsonOperation *op = (ParseJsonOperation *) import.steps.firstObject;
        NSURL *descriptorUrl = [report.url URLByAppendingPathComponent:@"metadata.json" isDirectory:NO];

        expect(op.jsonUrl).to.equal(descriptorUrl);
    });

    it(@"updates the report on the main thread after parsing the descriptor", ^{
        Report *report = mock([Report class]);
        [given([report url]) willReturn:[NSURL fileURLWithPath:@"/wherever/test_report" isDirectory:YES]];
        ExplodedHtmlImportProcess *import = [[ExplodedHtmlImportProcess alloc] initWithReport:report fileManager:fileManager];
        TestParseJsonOperation *modParseDescriptor = [[TestParseJsonOperation alloc] init];
        NSDictionary *descriptor = @{ @"title": @"On Main Thread" };
        modParseDescriptor.parsedJsonDictionary = descriptor;
        NSMutableArray<NSOperation *> *modSteps = [NSMutableArray array];
        [modSteps addObject:modParseDescriptor];
        import.steps = modSteps;

        __block BOOL updatedOnMainThread = NO;
        [given([report setPropertiesFromJsonDescriptor:descriptor]) willDo:(id)^(NSInvocation *invocation) {
            updatedOnMainThread = ([NSThread mainThread] == [NSThread currentThread]);
            return nil;
        }];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [import stepWillFinish:modParseDescriptor];
        });

        assertWithTimeout(1.0, thatEventually(@(updatedOnMainThread)), isTrue());

        stopMocking(report);
    });

    it(@"notifies the delegate on the main thread when finished", ^{
        Report *report = [[Report alloc] init];
        report.url = [reportsDir URLByAppendingPathComponent:@"test_report" isDirectory:YES];
        ExplodedHtmlImportProcess *import = [[ExplodedHtmlImportProcess alloc] initWithReport:report fileManager:fileManager];
        ParseJsonOperation *parseDescriptor = (ParseJsonOperation *) import.steps.firstObject;
        TestParseJsonOperation *modParseDescriptor = [[TestParseJsonOperation alloc] init];
        NSDictionary *descriptor = @{ @"title": @"On Main Thread" };
        modParseDescriptor.jsonUrl = parseDescriptor.jsonUrl;
        modParseDescriptor.parsedJsonDictionary = descriptor;
        NSMutableArray<NSOperation *> *modSteps = [NSMutableArray array];
        [modSteps addObject:modParseDescriptor];
        import.steps = modSteps;

        __block BOOL delegateNotified = NO;
        id<ImportDelegate> importListener = mockProtocol(@protocol(ImportDelegate));
        [givenVoid([importListener importDidFinishForImportProcess:import]) willDo:^id(NSInvocation *invocation) {
            delegateNotified = [NSThread currentThread] == [NSThread mainThread];
            return nil;
        }];
        import.delegate = importListener;

        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops addOperations:import.steps waitUntilFinished:NO];

        assertWithTimeout(1.0, thatEventually(@(delegateNotified)), isTrue());
    });

    afterEach(^{

    });

    afterAll(^{

    });
});

SpecEnd
