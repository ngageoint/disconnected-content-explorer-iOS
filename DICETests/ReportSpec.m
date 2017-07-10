//
//  ReportSpec.m
//  DICE
//
//  Created by Robert St. John on 8/11/15.
//  Copyright 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>

#import "Report.h"
#import <stdatomic.h>
#import <MagicalRecord/MagicalRecord.h>
#import "KVOBlockObserver.h"
#import "DICEConstants.h"



SpecBegin(Report)

describe(@"Report", ^{

    __block NSManagedObjectContext *context;

    beforeEach(^{

        [MagicalRecord setupCoreDataStackWithInMemoryStore];
        context = [NSManagedObjectContext MR_defaultContext];
    });

    afterEach(^{

        context = nil;
        [MagicalRecord cleanUp];
    });

    describe(@"transient cached attributes", ^{

        static NSString * const kPersistentAttr = @"persistentKey";
        static NSString * const kPersistentValue = @"persistentValue";
        static NSString * const kTransientAttr = @"transientKey";
        static NSString * const kTransientValue = @"transientValue";
        static NSString * const kValidatingAttrs = @"validatingAttrs";

        sharedExamplesFor(@"a kvo compliant derived transient attribute", ^(NSDictionary *data) {

            it(@"sets the persistent value from the transient value", ^{

                NSString *persistentAttr = data[kPersistentAttr];
                id persistentValue = data[kPersistentValue];
                NSString *transientAttr = data[kTransientAttr];
                id transientValue = data[kTransientValue];

                Report *report = [Report MR_createEntityInContext:context];
                NSKeyValueObservingOptions kvoOptions = NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
                KVOBlockObserver *persistentKvo = [KVOBlockObserver recordObservationsOfKeyPath:persistentAttr ofObject:report options:kvoOptions];
                KVOBlockObserver *transientKvo = [KVOBlockObserver recordObservationsOfKeyPath:transientAttr ofObject:report options:kvoOptions];

                [report setValue:transientValue forKey:transientAttr];

                expect([report valueForKey:persistentAttr]).to.equal(persistentValue);
                expect([report valueForKey:transientAttr]).to.equal(transientValue);
                expect(report.hasPersistentChangedValues).to.beTruthy();
                assertThat(report.changedValues, hasKey(persistentAttr));
                expect(persistentKvo.observations).to.haveCount(2);
                expect(persistentKvo.observations[0].isPrior).to.beTruthy();
                expect(persistentKvo.observations[1].isPrior).to.beFalsy();
                expect(persistentKvo.observations[1].oldValue).to.equal(NSNull.null);
                expect(persistentKvo.observations[1].newValue).to.equal(persistentValue);
                expect(transientKvo.observations).to.haveCount(2);
                expect(transientKvo.observations[0].isPrior).to.beTruthy();
                expect(transientKvo.observations[1].isPrior).to.beFalsy();
                expect(transientKvo.observations[1].oldValue).to.equal(NSNull.null);
                expect(transientKvo.observations[1].newValue).to.equal(transientValue);

                [report removeObserver:persistentKvo forKeyPath:persistentAttr];
                [report removeObserver:transientKvo forKeyPath:transientAttr];
            });

            it(@"sets the transient value from the persistent value", ^{

                NSString *persistentAttr = data[kPersistentAttr];
                id persistentValue = data[kPersistentValue];
                NSString *transientAttr = data[kTransientAttr];
                id transientValue = data[kTransientValue];

                Report *report = [Report MR_createEntityInContext:context];
                NSKeyValueObservingOptions kvoOptions = NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
                KVOBlockObserver *persistentKvo = [KVOBlockObserver recordObservationsOfKeyPath:persistentAttr ofObject:report options:kvoOptions];
                KVOBlockObserver *transientKvo = [KVOBlockObserver recordObservationsOfKeyPath:transientAttr ofObject:report options:kvoOptions];

                [report setValue:persistentValue forKey:persistentAttr];

                expect([report valueForKey:persistentAttr]).to.equal(persistentValue);
                expect([report valueForKey:transientAttr]).to.equal(transientValue);
                expect(report.hasPersistentChangedValues).to.beTruthy();
                assertThat(report.changedValues, hasKey(persistentAttr));
                expect(persistentKvo.observations).to.haveCount(2);
                expect(persistentKvo.observations[0].isPrior).to.beTruthy();
                expect(persistentKvo.observations[1].isPrior).to.beFalsy();
                expect(persistentKvo.observations[1].oldValue).to.equal(NSNull.null);
                expect(persistentKvo.observations[1].newValue).to.equal(persistentValue);
                expect(transientKvo.observations).to.haveCount(2);
                expect(transientKvo.observations[0].isPrior).to.beTruthy();
                expect(transientKvo.observations[1].isPrior).to.beFalsy();
                expect(transientKvo.observations[1].oldValue).to.equal(NSNull.null);
                expect(transientKvo.observations[1].newValue).to.equal(transientValue);

                [report removeObserver:persistentKvo forKeyPath:persistentAttr];
                [report removeObserver:transientKvo forKeyPath:transientAttr];
            });

            it(@"wraps attribute access", ^{

                NSString *persistentAttr = data[kPersistentAttr];
                id persistentValue = data[kPersistentValue];
                NSString *transientAttr = data[kTransientAttr];
                id transientValue = data[kTransientValue];
                NSDictionary *otherAttrs = data[kValidatingAttrs];

                Report *report = [Report MR_createEntityInContext:context];
                if (otherAttrs) {
                    [report setValuesForKeysWithDictionary:otherAttrs];
                }
                report.sourceFileUrl = @"file:///dice/test.zip";
                [report setValue:persistentValue forKey:persistentAttr];

                expect([context save:NULL]).to.beTruthy();
                expect(report.isFault).to.beFalsy();

                [context refreshObject:report mergeChanges:NO];

                expect(report.isFault).to.beTruthy();

                SEL accessorSelector = NSSelectorFromString(transientAttr);
                IMP accessorMethod = [report methodForSelector:accessorSelector];
                id (*callAccessor)(id, SEL) = (void *)accessorMethod;
                id value = callAccessor(report, accessorSelector);

                expect(report.isFault).to.beFalsy();
                expect(value).to.equal(transientValue);
                expect([report primitiveValueForKey:persistentAttr]).to.equal(persistentValue);

                [context refreshObject:report mergeChanges:NO];

                expect(report.isFault).to.beTruthy();

                accessorSelector = NSSelectorFromString(persistentAttr);
                accessorMethod = [report methodForSelector:accessorSelector];
                callAccessor = (void *)accessorMethod;
                value = callAccessor(report, accessorSelector);

                expect(report.isFault).to.beFalsy();
                expect(value).to.equal(persistentValue);
                expect([report primitiveValueForKey:transientAttr]).to.equal(transientValue);
            });

            it(@"sets the transient value on fetch", ^{

                NSString *persistentAttr = data[kPersistentAttr];
                id persistentValue = data[kPersistentValue];
                NSString *transientAttr = data[kTransientAttr];
                id transientValue = data[kTransientValue];
                NSDictionary *otherAttrs = data[kValidatingAttrs];

                Report *report = [Report MR_createEntityInContext:context];
                if (otherAttrs) {
                    [report setValuesForKeysWithDictionary:otherAttrs];
                }
                [report setValue:persistentValue forKey:persistentAttr];

                __block BOOL saved = NO;
                __block NSError *saveError;
                waitUntilTimeout(1.0, ^(DoneCallback done) {
                    [context MR_saveToPersistentStoreWithCompletion:^(BOOL contextDidSave, NSError * _Nullable error) {
                        saved = contextDidSave;
                        saveError = error;
                        done();
                    }];
                });

                NSManagedObjectContext *fetchContext = [NSManagedObjectContext MR_contextWithParent:[NSManagedObjectContext MR_rootSavingContext]];
                Report *fetched = [report MR_inContext:fetchContext];

                expect(saved).to.beTruthy();
                expect(saveError).to.beNil();
                expect([fetched valueForKey:transientAttr]).to.equal(transientValue);
                expect([fetched valueForKey:persistentAttr]).to.equal(persistentValue);
            });
        });

        describe(@"remoteSource", ^{

            itBehavesLike(@"a kvo compliant derived transient attribute", ^{

                NSURL *remoteSource = [NSURL URLWithString:@"http://dice.com/test"];
                return @{
                    kPersistentAttr: @"remoteSourceUrl",
                    kPersistentValue: @"http://dice.com/test",
                    kTransientAttr: @"remoteSource",
                    kTransientValue: remoteSource
                };
            });
        });

        describe(@"sourceFile", ^{

            itBehavesLike(@"a kvo compliant derived transient attribute", ^{

                NSURL *sourceFile = [NSURL fileURLWithPath:@"/dice/test.zip" isDirectory:NO];
                return @{
                    kPersistentAttr: @"sourceFileUrl",
                    kPersistentValue: @"file:///dice/test.zip",
                    kTransientAttr: @"sourceFile",
                    kTransientValue: sourceFile
                };
            });
        });

        describe(@"importDir", ^{

            itBehavesLike(@"a kvo compliant derived transient attribute", ^{

                NSURL *importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import" isDirectory:YES];
                return @{
                    kPersistentAttr: @"importDirUrl",
                    kPersistentValue: @"file:///dice/test.dice_import/",
                    kTransientAttr: @"importDir",
                    kTransientValue: importDir,
                    kValidatingAttrs: @{
                        @"sourceFileUrl": @"file:///dice/test.zip"
                    }
                };
            });
        });

        describe(@"baseDir", ^{

            itBehavesLike(@"a kvo compliant derived transient attribute", ^{

                NSURL *baseDir = [NSURL fileURLWithPath:@"/dice/test.dice_import/content" isDirectory:YES];
                return @{
                    kPersistentAttr: @"baseDirUrl",
                    kPersistentValue: @"file:///dice/test.dice_import/content/",
                    kTransientAttr: @"baseDir",
                    kTransientValue: baseDir,
                    kValidatingAttrs: @{
                        @"sourceFileUrl": @"file:///dice/test.zip",
                        @"importDirUrl": @"file:///dice/test.zip.dice_import/"
                    }
                };
            });
        });

        describe(@"rootFile", ^{

            itBehavesLike(@"a kvo compliant derived transient attribute", ^{

                NSURL *rootFile = [NSURL fileURLWithPath:@"/dice/test.dice_import/content/index.html" isDirectory:NO];
                return @{
                    kPersistentAttr: @"rootFileUrl",
                    kPersistentValue: @"file:///dice/test.dice_import/content/index.html",
                    kTransientAttr: @"rootFile",
                    kTransientValue: rootFile,
                    kValidatingAttrs: @{
                        @"sourceFileUrl": @"file:///dice/test.zip",
                        @"importDirUrl": @"file:///dice/test.zip.dice_import/",
                        @"baseDirUrl": @"file:///dice/test.zip.dice_import/content"
                    }
                };
            });
        });
    });

    describe(@"validation", ^{

        NSString * const kMakeValid = @"makeValid";
        NSString * const kMakeInvalid = @"makeInvalid";
        NSString * const kErrorCode = @"errorCode";

        sharedExamplesFor(@"an entity with common insert and update validation", ^(NSDictionary *data) {

            it(@"is invalid for insert and update with expected error code", ^{

                NSNumber *errorCode = data[kErrorCode];
                void (^makeEntityInvalid)(Report *) = data[kMakeInvalid];
                void (^makeEntityValid)(Report *) = data[kMakeValid];
                __block NSError *error = nil;

                Report *report = [Report MR_createEntityInContext:context];
                makeEntityInvalid(report);

                expect([report validateForInsert:&error]).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);

                error = nil;

                expect([report validateForUpdate:&error]).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);

                error = nil;

                expect([context save:&error]).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);

                makeEntityValid(report);

                expect([report validateForInsert:&error]).to.beTruthy();
                expect(error).to.beNil();

                expect([report validateForUpdate:&error]).to.beTruthy();
                expect(error).to.beNil();

                expect([context save:&error]).to.beTruthy();
                expect(error).to.beNil();

                makeEntityInvalid(report);

                expect([report validateForInsert:&error]).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);

                error = nil;

                expect([report validateForUpdate:&error]).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);
                
                error = nil;
                
                expect([context save:&error]).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);
            });
        });

        describe(@"source file validation", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFile = nil;
                    report.remoteSource = nil;
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidSourceUrlErrorCode)
                };
            });
        });

        describe(@"remote source validation", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFile = nil;
                    report.remoteSource = nil;
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.remoteSourceUrl = @"http://dice.com/test.zip";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidSourceUrlErrorCode)
                };
            });
        });

        describe(@"source file + remote source validation", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFile = nil;
                    report.remoteSource = nil;
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.remoteSourceUrl = @"http://dice.com/test.zip";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidSourceUrlErrorCode)
                };
            });
        });

        describe(@"baseDir requires importDir", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = nil;
                    report.baseDirUrl = @"file:///dice/test.zip.dice_import/content/";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirUrl = @"file:///dice/test.zip.dice_import/content/";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidImportDirErrorCode)
                };
            });
        });

        describe(@"rootFile requires baseDir", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirUrl = nil;
                    report.rootFileUrl = @"file:///dice/test.zip.dice_import/content/index.html";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirUrl = @"file:///dice/test.zip.dice_import/content/";
                    report.rootFileUrl = @"file:///dice/test.zip.dice_import/content/index.html";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidBaseDirErrorCode)
                };
            });
        });

        it(@"validates base dir is child of import dir", ^{

        });

        it(@"validates thumbnail path is relative", ^{

        });

        it(@"validates tile thumbnail path is relative", ^{

        });

    });

    it(@"appends thumbnail path to base dir for thumbnail url", ^{

        Report *report = [Report MR_createEntityInContext:context];
        report.importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import" isDirectory:YES];
        report.baseDir = [report.importDir URLByAppendingPathComponent:@"content" isDirectory:YES];
        report.thumbnailPath = @"images/thumbnail.png";

        expect(report.thumbnail).to.equal([NSURL fileURLWithPath:@"/dice/test.dice_import/content/images/thumbnail.png" isDirectory:NO]);
        expect(report.thumbnailPath).to.equal(@"images/thumbnail.png");
    });

    it(@"appends tile thumbnail path to base dir for tile thumbnail url", ^{

        Report *report = [Report MR_createEntityInContext:context];
        report.importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import" isDirectory:YES];
        report.baseDir = [report.importDir URLByAppendingPathComponent:@"content" isDirectory:YES];
        report.tileThumbnailPath = @"images/thumbnail.png";

        expect(report.tileThumbnail).to.equal([NSURL fileURLWithPath:@"/dice/test.dice_import/content/images/thumbnail.png" isDirectory:NO]);
        expect(report.tileThumbnailPath).to.equal(@"images/thumbnail.png");
    });

    it(@"updates report from json descriptor", ^{

        Report *report = [Report MR_createEntityInContext:context];

        [report setPropertiesFromJsonDescriptor:@{
            @"contentId": @"abc123",
            @"title": @"JSON Test",
            @"description": @"Test the JSON meta-data mechanism",
            @"lat": @39.8,
            @"lon": @-104.8,
            @"thumbnail": @"images/test.png",
            @"tile_thumbnail": @"images/test-tile.png",
        }];

        expect(report.contentId).to.equal(@"abc123");
        expect(report.title).to.equal(@"JSON Test");
        expect(report.summary).to.equal(@"Test the JSON meta-data mechanism");
        expect(report.lat).to.equal(@39.8);
        expect(report.lon).to.equal(@-104.8);
        expect(report.thumbnailPath).to.equal(@"images/test.png");
        expect(report.tileThumbnailPath).to.equal(@"images/test-tile.png");
        expect(report.importStatus).to.equal(ReportImportStatusNew);
        expect(report.isImportFinished).to.equal(NO);
    });

    it(@"leaves properties not in the descriptor intact", ^{

        Report *report = [Report MR_createEntityInContext:context];

        report.contentId = @"org.dice.test";
        report.title = @"Test";
        report.summary = @"It's a test";
        report.lat = nil;
        report.lon = nil;
        report.thumbnailPath = @"test/default.png";
        report.tileThumbnailPath = @"test/default_tile.png";

        [report setPropertiesFromJsonDescriptor:@{
            @"description": @"new description",
            @"tile_thumbnail": @"my_tile.png",
        }];

        expect(report.contentId).to.equal(@"org.dice.test");
        expect(report.title).to.equal(@"Test");
        expect(report.summary).to.equal(@"new description");
        expect(report.lat).to.beNil();
        expect(report.lon).to.beNil();
        expect(report.thumbnailPath).to.equal(@"test/default.png");
        expect(report.tileThumbnailPath).to.equal(@"my_tile.png");
        expect(report.importStatus).to.equal(ReportImportStatusNew);
        expect(report.isImportFinished).to.equal(NO);
    });

    it(@"indicates import finished when status is success or failed", ^{

        Report *report = [Report MR_createEntityInContext:context];

        expect(report.importStatus).to.equal(ReportImportStatusNew);
        expect(report.isImportFinished).to.equal(NO);

        report.importStatus = ReportImportStatusDownloading;
        expect(report.isImportFinished).to.equal(NO);

        report.importStatus = ReportImportStatusExtracting;
        expect(report.isImportFinished).to.equal(NO);

        report.importStatus = ReportImportStatusImporting;
        expect(report.isImportFinished).to.equal(NO);

        report.importStatus = ReportImportStatusFailed;
        expect(report.isImportFinished).to.equal(YES);

        report.importStatus = ReportImportStatusSuccess;
        expect(report.isImportFinished).to.equal(YES);
    });

    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
