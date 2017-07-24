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
#import <objc/runtime.h>


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

    it(@"is synced to the model", ^{

        NSSet<NSString *> *customEntityAttributes = [NSSet setWithObjects:
            @"importDir",
            @"remoteSource",
            @"sourceFile",
            nil];

        NSSet<NSString *> *nonModelHelpers = [NSSet setWithObjects:
            @"baseDir",
            @"cacheFiles",
            @"downloadPercent",
            @"isImportFinished",
            @"rootFile",
            @"tileThumbnail",
            @"thumbnail",
            nil];

        NSEntityDescription *entity = [NSEntityDescription entityForName:@"Report" inManagedObjectContext:context];
        for (NSPropertyDescription *entityProp in entity.properties) {
            const char *propName = entityProp.name.UTF8String;
            objc_property_t prop = class_getProperty(Report.class, propName);

            BOOL isDynamic = NO;
            if (prop) {
                const char *attrs = property_getAttributes(prop);
                NSString *attrStr = [NSString stringWithUTF8String:attrs];
                NSArray<NSString *> *components = [attrStr componentsSeparatedByString:@","];
                isDynamic = [components containsObject:@"D"];
                if (!isDynamic && ![customEntityAttributes containsObject:entityProp.name]) {
                    failure([NSString stringWithFormat:@"non-custom property %@ is not @dynamic", entityProp.name]);
                }
            }
            else {
                failure([NSString stringWithFormat:@"no declared property for model-defined attribute %@", entityProp.name]);
            }
        }

        unsigned int propCount;
        objc_property_t *props = class_copyPropertyList(Report.class, &propCount);
        for (int p = 0; p < propCount; p++) {
            objc_property_t prop = props[p];
            const char *propName = property_getName(prop);
            NSString *propNameStr = [NSString stringWithUTF8String:propName];
            if (!entity.propertiesByName[propNameStr] && ![nonModelHelpers containsObject:propNameStr]) {
                failure([NSString stringWithFormat:@"non-helper property %@ has no associated model attribute", propNameStr]);
            }
        }
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

                expect(saved).to.beTruthy();
                expect(saveError).to.beNil();

                NSManagedObjectContext *fetchContext = [NSManagedObjectContext MR_contextWithParent:[NSManagedObjectContext MR_rootSavingContext]];
                NSManagedObjectID *reportId = report.objectID;
                [fetchContext performBlockAndWait:^{
                    NSError *error;
                    Report *fetched = [fetchContext objectWithID:reportId];

                    expect(fetched).toNot.beNil();
                    expect(error).to.beNil();

                    id fetchedTransientValue = [fetched valueForKey:transientAttr];
                    id fetchedPersistentValue = [fetched valueForKey:persistentAttr];

                    expect(fetchedTransientValue).to.equal(transientValue);
                    expect(fetchedPersistentValue).to.equal(persistentValue);
                }];
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

                BOOL valid = [report validateForInsert:&error];
                expect(valid).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);
                expect(error.domain).to.equal(DICEPersistenceErrorDomain);

                error = nil;

                valid = [report validateForUpdate:&error];
                expect(valid).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);
                expect(error.domain).to.equal(DICEPersistenceErrorDomain);

                error = nil;

                valid = [context save:&error];
                expect(valid).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);
                expect(error.domain).to.equal(DICEPersistenceErrorDomain);

                makeEntityValid(report);

                valid = [report validateForInsert:&error];
                expect(valid).to.beTruthy();
                expect(error).to.beNil();

                valid = [report validateForUpdate:&error];
                expect(valid).to.beTruthy();
                expect(error).to.beNil();

                valid = [context save:&error];
                expect(valid).to.beTruthy();
                expect(error).to.beNil();

                makeEntityInvalid(report);
                valid = [report validateForInsert:&error];

                expect(valid).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);
                expect(error.domain).to.equal(DICEPersistenceErrorDomain);

                error = nil;
                valid = [report validateForUpdate:&error];

                expect(valid).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);
                expect(error.domain).to.equal(DICEPersistenceErrorDomain);
                
                error = nil;
                valid = [context save:&error];
                
                expect(valid).to.beFalsy();
                expect(error).toNot.beNil();
                expect(error.code).to.equal(errorCode.unsignedIntegerValue);
                expect(error.domain).to.equal(DICEPersistenceErrorDomain);
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
                    report.baseDirName = @"content";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidBaseDirErrorCode)
                };
            });
        });

        describe(@"rootFile requires baseDir", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = nil;
                    report.rootFilePath = @"index.html";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.rootFilePath = @"index.html";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidRootFileErrorCode)
                };
            });
        });

        describe(@"baseDirName must be single path component", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"multiple/components";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"single_component";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidBaseDirErrorCode)
                };
            });
            
            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"/leading_slash";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"relative";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidBaseDirErrorCode)
                };
            });
        });

        describe(@"rootFilePath must be relative", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.rootFilePath = @"/index.html";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.rootFilePath = @"index.html";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidRootFileErrorCode)
                };
            });
            
            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.rootFilePath = @"/nested/index.html";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.rootFilePath = @"nested/index.html";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidRootFileErrorCode)
                };
            });
        });

        describe(@"thubnailPath requires baseDir", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = nil;
                    report.thumbnailPath = @"img/thumb.png";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.thumbnailPath = @"img/thumb.png";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidBaseDirErrorCode)
                };
            });
        });

        describe(@"tileThumbnailPath requires baseDir", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = nil;
                    report.tileThumbnailPath = @"img/tile.png";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.tileThumbnailPath = @"img/tile.png";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidBaseDirErrorCode)
                };
            });
        });

        describe(@"thumbnailPath must be relative", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.thumbnailPath = @"/dice/test.zip.dice_import/content/thumb.png";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.thumbnailPath = @"img/thumb.png";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidThumbnailErrorCode)
                };
            });
        });

        describe(@"tileThumbnailPath must be relative", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.tileThumbnailPath = @"/dice/test.zip.dice_import/content/tile.png";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.tileThumbnailPath = @"img/tile.png";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidThumbnailErrorCode)
                };
            });
        });

        describe(@"thumbnails cannot be empty strings", ^{

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.thumbnailPath = @"";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.thumbnailPath = @"img/tile.png";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidThumbnailErrorCode)
                };
            });

            itBehavesLike(@"an entity with common insert and update validation", ^{

                void (^makeInvalid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.tileThumbnailPath = @"";
                };
                void (^makeValid)(Report *report) = ^(Report *report) {
                    report.sourceFileUrl = @"file:///dice/test.zip";
                    report.importDirUrl = @"file:///dice/test.zip.dice_import/";
                    report.baseDirName = @"content";
                    report.tileThumbnailPath = @"img/tile.png";
                };
                return @{
                    kMakeInvalid: makeInvalid,
                    kMakeValid: makeValid,
                    kErrorCode: @(DICEInvalidThumbnailErrorCode)
                };
            });
        });
    });

    it(@"sets dateAdded to now on creation", ^{

        Report *report = [Report MR_createEntityInContext:context];

        assertThatDouble(report.dateAdded.timeIntervalSinceReferenceDate, closeTo([NSDate date].timeIntervalSinceReferenceDate, 0.001));
    });

    it(@"sets dateLastAccessed to now on creation", ^{

        Report *report = [Report MR_createEntityInContext:context];

        assertThatDouble(report.dateAdded.timeIntervalSinceReferenceDate, closeTo([NSDate date].timeIntervalSinceReferenceDate, 0.001));
    });

    it(@"appends base dir name to import dir for base dir url", ^{

        Report *report = [Report MR_createEntityInContext:context];
        report.importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import"];
        report.baseDirName = @"content";

        expect(report.baseDir).to.equal([NSURL fileURLWithPath:@"/dice/test.dice_import/content" isDirectory:YES]);
    });

    it(@"appends root file path to base dir url for root file url", ^{
        Report *report = [Report MR_createEntityInContext:context];
        report.importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import"];
        report.baseDirName = @"content";
        report.rootFilePath = @"index.html";

        expect(report.rootFile).to.equal([NSURL fileURLWithPath:@"/dice/test.dice_import/content/index.html" isDirectory:NO]);

        report.rootFilePath = @"nested/index.html";

        expect(report.rootFile).to.equal([NSURL fileURLWithPath:@"/dice/test.dice_import/content/nested/index.html" isDirectory:NO]);
    });

    it(@"returns nil base dir if import dir or base dir name is nil", ^{

        Report *report = [Report MR_createEntityInContext:context];
        report.importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import"];
        report.baseDirName = nil;

        expect(report.baseDir).to.beNil();

        report.importDir = nil;
        report.baseDirName = @"content";

        expect(report.baseDir).to.beNil();
    });

    it(@"returns nil root file if base dir name is nil", ^{

        Report *report = [Report MR_createEntityInContext:context];
        report.importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import"];
        report.baseDirName = nil;

        expect(report.rootFile).to.beNil();
    });

    it(@"appends thumbnail path to base dir for thumbnail url", ^{

        Report *report = [Report MR_createEntityInContext:context];
        report.importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import" isDirectory:YES];
        report.baseDirName = @"content";
        report.thumbnailPath = @"images/thumbnail.png";

        expect(report.thumbnail).to.equal([NSURL fileURLWithPath:@"/dice/test.dice_import/content/images/thumbnail.png" isDirectory:NO]);
        expect(report.thumbnailPath).to.equal(@"images/thumbnail.png");
    });

    it(@"appends tile thumbnail path to base dir for tile thumbnail url", ^{

        Report *report = [Report MR_createEntityInContext:context];
        report.importDir = [NSURL fileURLWithPath:@"/dice/test.dice_import" isDirectory:YES];
        report.baseDirName = @"content";
        report.tileThumbnailPath = @"images/thumbnail.png";

        expect(report.tileThumbnail).to.equal([NSURL fileURLWithPath:@"/dice/test.dice_import/content/images/thumbnail.png" isDirectory:NO]);
        expect(report.tileThumbnailPath).to.equal(@"images/thumbnail.png");
    });

    it(@"intializes cache files", ^{

        Report *report = [Report MR_createEntityInContext:context];

        expect(report.cacheFiles).toNot.beNil();

        report.sourceFileUrl = @"file:///dice/test.zip";
        [context MR_saveToPersistentStoreAndWait];

        NSManagedObjectContext *fetchContext = [NSManagedObjectContext MR_context];
        [fetchContext performBlockAndWait:^{
            Report *fetched = [fetchContext existingObjectWithID:report.objectID error:NULL];

            expect(fetched.cacheFiles).toNot.beNil();
        }];
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
            @"tileThumbnail": @"images/test-tile.png",
        }];

        expect(report.contentId).to.equal(@"abc123");
        expect(report.title).to.equal(@"JSON Test");
        expect(report.summary).to.equal(@"Test the JSON meta-data mechanism");
        expect(report.lat).to.equal(@39.8);
        expect(report.lon).to.equal(@-104.8);
        expect(report.thumbnailPath).to.equal(@"images/test.png");
        expect(report.tileThumbnailPath).to.equal(@"images/test-tile.png");
        expect(report.importState).to.equal(ReportImportStatusNew);
        expect(report.importStateToEnter).to.equal(ReportImportStatusNew);
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
            @"tileThumbnail": @"my_tile.png",
        }];

        expect(report.contentId).to.equal(@"org.dice.test");
        expect(report.title).to.equal(@"Test");
        expect(report.summary).to.equal(@"new description");
        expect(report.lat).to.beNil();
        expect(report.lon).to.beNil();
        expect(report.thumbnailPath).to.equal(@"test/default.png");
        expect(report.tileThumbnailPath).to.equal(@"my_tile.png");
        expect(report.importState).to.equal(ReportImportStatusNew);
        expect(report.importStateToEnter).to.equal(ReportImportStatusNew);
        expect(report.isImportFinished).to.equal(NO);
    });

    it(@"indicates import finished when status is success or failed", ^{

        Report *report = [Report MR_createEntityInContext:context];

        ReportImportStatus incomplete[9] = {
            ReportImportStatusNew,
            ReportImportStatusDownloading,
            ReportImportStatusInspectingSourceFile,
            ReportImportStatusInspectingArchive,
            ReportImportStatusExtractingContent,
            ReportImportStatusInspectingContent,
            ReportImportStatusMovingContent,
            ReportImportStatusDeleting,
            ReportImportStatusDeleted,
        };

        NSUInteger remaining = 9;
        while (remaining) {
            remaining -= 1;
            report.importState = incomplete[remaining];
            NSUInteger combo = 9;
            while (combo) {
                combo -= 1;
                report.importStateToEnter = incomplete[combo];
                if (report.isImportFinished) {
                    failure([NSString stringWithFormat:@"current %d, entering %d", report.importState, report.importStateToEnter]);
                }
            }

            report.importStateToEnter = ReportImportStatusSuccess;
            if (report.isImportFinished) {
                failure([NSString stringWithFormat:@"current %d, entering %d", report.importState, report.importStateToEnter]);
            }
            report.importStateToEnter = ReportImportStatusFailed;
            if (report.isImportFinished) {
                failure([NSString stringWithFormat:@"current %d, entering %d", report.importState, report.importStateToEnter]);
            }

            report.importStateToEnter = report.importState;
            report.importState = ReportImportStatusSuccess;
            if (report.isImportFinished) {
                failure([NSString stringWithFormat:@"current %d, entering %d", report.importState, report.importStateToEnter]);
            }
            report.importState = ReportImportStatusFailed;
            if (report.isImportFinished) {
                failure([NSString stringWithFormat:@"current %d, entering %d", report.importState, report.importStateToEnter]);
            }
        }

        report.importState = ReportImportStatusFailed;
        report.importStateToEnter = ReportImportStatusFailed;
        expect(report.isImportFinished).to.beTruthy();
        report.importStateToEnter = ReportImportStatusSuccess;
        expect(report.isImportFinished).to.beFalsy();

        report.importState = ReportImportStatusSuccess;
        report.importStateToEnter = ReportImportStatusSuccess;
        expect(report.isImportFinished).to.beTruthy();
        report.importStateToEnter = ReportImportStatusFailed;
        expect(report.isImportFinished).to.beFalsy();
    });

    afterEach(^{

    });
    
    afterAll(^{

    });
});

SpecEnd
