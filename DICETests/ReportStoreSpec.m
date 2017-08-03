#import "Report.h"
#import "Specta.h"
#import "SpectaUtility.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <JGMethodSwizzler/JGMethodSwizzler.h>
#import <MagicalRecord/MagicalRecord.h>

#import "DICEArchive.h"
#import "DICEExtractReportOperation.h"
#import "FileOperations.h"
#import "ImportProcess+Internal.h"
#import "NotificationRecordingObserver.h"
#import "NSOperation+Blockable.h"
#import "NSString+PathUtils.h"
#import "ReportStore.h"
#import "ReportType.h"
#import "TestDICEArchive.h"
#import "TestOperationQueue.h"
#import "TestReportType.h"
#import "DICEUtiExpert.h"
#import "MatchReportTypeToContentAtPathOperation.h"
#import "TestFileManager.h"
#import "NSFileManager+Convenience.h"
#import <stdatomic.h>
#import <objc/runtime.h>

/*
 NOTE: The reason for all of the [Report willAccessValueForKey:] calls is
 to ensure an explicitly saved object is not a fault.  This requirement
 became apparent when writing the "transitions from downloading to inspecting
 source file" test.  The test called [ReportStore downloadManager:willFinishDownload:movingToFile:]
 which used [NSManagedObjectContext performBlock:] to asyncronously set the
 sourceFile on the Report and save the Report.  At the time, the test then
 sequentially attempted to assert that the main-thread instance of the Report had the
 proper sourceFile value, which should have failed.  However, the test was
 passing because the Report that was created at the beginng of the test and persisted
 on the main context was still a fault.  When the assertion on the sourceFile accessed
 the sourceFile property, core data's fault mechanism activated to fetch the entity.
 Debugging showed that the within the willAccessValueForKey: method, the main thread 
 was blocked on a semaphore wait, invoked as a result of submitting a block of work to
 the private queue context.  The main thread then waited until the background block
 finished before returning from firing the fault and the sourceFile property accessor, 
 so main context entity was able to fetch the value the background block had assigned.
 See the "core data concurrency" tests at the end as well.
 */


/**
 This category enables the OCHamcrest endsWith matcher to accept
 NSURL objects.
 */
@interface NSURL (HasSuffixSupport)

- (BOOL)hasSuffix:(NSString *)suffix;

@end

@implementation NSURL (HasSuffixSupport)

- (BOOL)hasSuffix:(NSString *)suffix
{
    return [self.path hasSuffix:suffix];
}

@end


@interface NSNotification (ReportStoreSpec)

@property (readonly) NSSet<Report *> *insertedObjects;
@property (readonly) NSSet<Report *> *updatedObjects;
@property (readonly) NSSet<Report *> *deletedObjects;

@end

@implementation NSNotification (ReportStoreSpec)

- (NSSet<Report *> *)insertedObjects
{
    return self.userInfo[NSInsertedObjectsKey];
}
- (NSSet<Report *> *)updatedObjects
{
    return self.userInfo[NSUpdatedObjectsKey];
}
- (NSSet<Report *> *)deletedObjects
{
    return self.userInfo[NSDeletedObjectsKey];
}

@end


@interface NSSet (ReportStoreSpec)

- (Report *)reportWithSourceUrl:(NSURL *)url;

@end

@implementation NSSet (ReportStoreSpec)

- (Report *)reportWithSourceUrl:(NSURL *)url
{
    for (Report *report in self) {
        if ([url isEqual:report.sourceFile] || [url isEqual:report.remoteSource]) {
            return report;
        }
    }
    return nil;
}

@end


@interface NSManagedObjectContext (ReportStoreSpect)

- (id)observe:(NSString *)name withBlock:(void ((^)(NSNotification *note)))block;
- (void)removeNotificationObserver:(id)observer;
- (void)clearNotificationObservers;
- (void)waitForQueueToDrain;

@end

@implementation NSManagedObjectContext (ReportStoreSpec)

static void *kObservers = &kObservers;

- (id)observe:(NSString *)name withBlock:(void ((^)(NSNotification *note)))block
{
    NSMutableArray *observers = objc_getAssociatedObject(self, kObservers);
    if (observers == nil) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, kObservers, observers, OBJC_ASSOCIATION_RETAIN);
    }
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:self queue:nil usingBlock:block];
    [observers addObject:observer];
    return observer;
}

- (void)removeNotificationObserver:(id)observer
{
    [NSNotificationCenter.defaultCenter removeObserver:observer name:nil object:self];
    NSMutableArray *observers = objc_getAssociatedObject(self, kObservers);
    [observers removeObject:observer];
}

- (void)clearNotificationObservers
{
    NSMutableArray *observers = objc_getAssociatedObject(self, kObservers);
    NSUInteger remaining = observers.count;
    while (remaining) {
        remaining -= 1;
        id observer = observers[remaining];
        [self removeNotificationObserver:observer];
    }
    objc_setAssociatedObject(self, kObservers, nil, OBJC_ASSOCIATION_ASSIGN);
}

- (void)waitForQueueToDrain
{
    waitUntil(^(DoneCallback done) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self performBlock:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    done();
                });
            }];
        });
    });
}

@end


static NSString * const UTI_RED = @"dice.test.red";
static NSString * const UTI_BLUE = @"dice.test.blue";


@interface TestDICEUtiExpert : DICEUtiExpert

@end


@implementation TestDICEUtiExpert

- (CFStringRef)probableUtiForResource:(NSURL *)resource conformingToUti:(CFStringRef)constraint
{
    if ([@"red" isEqualToString:resource.pathExtension]) {
        return (__bridge CFStringRef)UTI_RED;
    }
    else if ([@"blue" isEqualToString:resource.pathExtension]) {
        return (__bridge CFStringRef)UTI_BLUE;
    }
    return [super probableUtiForResource:resource conformingToUti:constraint];
}

- (CFStringRef)preferredUtiForExtension:(NSString *)ext conformingToUti:(CFStringRef)constraint
{
    if ([@"red" isEqualToString:ext]) {
        return (__bridge CFStringRef _Nullable)(UTI_RED);
    }
    else if ([@"blue" isEqualToString:ext]) {
        return (__bridge CFStringRef _Nullable)(UTI_BLUE);
    }
    return [super preferredUtiForExtension:ext conformingToUti:constraint];
}

@end


static dispatch_queue_t backgroundQueue;

void onMainThread(void(^block)())
{
    dispatch_sync(dispatch_get_main_queue(), block);
}

void onMainThreadLater(void(^block)())
{
    dispatch_async(dispatch_get_main_queue(), block);
}

void inBackground(void(^block)())
{
    dispatch_sync(backgroundQueue, block);
}

void inBackgroundLater(void(^block)())
{
    dispatch_async(backgroundQueue, block);
}


SpecBegin(ReportStore)

describe(@"NSFileManager", ^{

    it(@"returns directory url with trailing slash", ^{

        NSURL *resources = [[[NSBundle bundleForClass:[self class]] bundleURL] URLByAppendingPathComponent:@"etc" isDirectory:YES];
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:resources includingPropertiesForKeys:nil options:0 error:NULL];
        NSURL *dirUrl;
        for (NSURL *url in contents) {
            if ([url.lastPathComponent isEqualToString:@"a_directory"]) {
                dirUrl = url;
            }
        }

        expect([dirUrl.absoluteString hasSuffix:@"/"]).to.equal(YES);
        expect([dirUrl.path hasSuffix:@"/"]).to.equal(NO);

        NSString *resourceType;
        [dirUrl getResourceValue:&resourceType forKey:NSURLFileResourceTypeKey error:NULL];
        expect(resourceType).to.equal(NSURLFileResourceTypeDirectory);
    });

});

describe(@"dynamic utis", ^{

    __block CFStringRef uti1;

    beforeEach(^{

        uti1 = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)@"red", NULL);
    });

    it(@"creates a dynamic uti for an extension", ^{

        expect(UTTypeIsDynamic(uti1)).to.beTruthy();
    });

    it(@"retrieves the same uti for file extension in same process", ^{

        CFStringRef uti2 = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)@"red", NULL);

        expect(UTTypeIsDynamic(uti2)).to.beTruthy();
        expect(UTTypeEqual(uti1, uti2)).to.beTruthy();
        expect((__bridge NSString *)uti1).to.equal((__bridge NSString *)uti2);
    });
});

describe(@"ReportStore", ^{

    __block NSManagedObjectContext *reportDb;
    __block NSManagedObjectContext *verifyDb;
    __block NSFetchedResultsController *verifyResults;
    __block id<NSFetchedResultsControllerDelegate> verifyResultsDelegate;
    __block NSPredicate *isImportFinished;
    __block NSPredicate *hasSourceUrl;
    __block NSPredicate *sourceUrlIsFinished;
    __block TestReportType *redType;
    __block TestReportType *blueType;
    __block TestFileManager *fileManager;
    __block id<DICEArchiveFactory> archiveFactory;
    __block DICEDownloadManager *downloadManager;
    __block TestOperationQueue *importQueue;
    __block ReportStore *store;
    __block UIApplication *app;
    __block NSUInteger backgroundTaskId;
    __block void (^backgroundTaskHandler)(void);
    __block NSURL *reportsDir;
    __block NSMutableArray<NSNotification *> *saveNotes;
    __block NSMutableArray<NSNotification *> *changeNotes;

    beforeAll(^{
        backgroundQueue = dispatch_queue_create("ReportStoreSpec-bg-serial", DISPATCH_QUEUE_SERIAL);
    });

    beforeEach(^{

        [MagicalRecord setupCoreDataStackWithInMemoryStore];
        reportDb = [NSManagedObjectContext MR_rootSavingContext];
        verifyDb = [NSManagedObjectContext MR_defaultContext];
        NSFetchRequest *fetchRequest = [Report fetchRequest];
        fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"dateAdded" ascending:NO]];
        verifyResults = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest managedObjectContext:verifyDb sectionNameKeyPath:nil cacheName:nil];
        verifyResultsDelegate = mockProtocol(@protocol(NSFetchedResultsControllerDelegate));
        verifyResults.delegate = verifyResultsDelegate;
        isImportFinished = [NSPredicate predicateWithFormat:@"importState IN %@", @[@(ReportImportStatusFailed), @(ReportImportStatusSuccess)]];
        hasSourceUrl = [NSPredicate predicateWithFormat:@"sourceFileUrl == $url.absoluteString OR remoteSourceUrl == $url.absoluteString"];
        sourceUrlIsFinished = [NSCompoundPredicate andPredicateWithSubpredicates:@[hasSourceUrl, isImportFinished]];

        saveNotes = [NSMutableArray array];
        [reportDb observe:NSManagedObjectContextDidSaveNotification withBlock:^(NSNotification * _Nonnull note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [saveNotes addObject:note];
            });
        }];
        changeNotes = [NSMutableArray array];
        [reportDb observe:NSManagedObjectContextObjectsDidChangeNotification withBlock:^(NSNotification * _Nonnull note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [changeNotes addObject:note];
            });
        }];

        NSString *testNameComponent = ((SPTSpec *)SPTCurrentSpec).name;
        NSRange doubleUnderscore = [testNameComponent rangeOfString:@"__" options:NSBackwardsSearch];
        testNameComponent = [testNameComponent substringFromIndex:doubleUnderscore.location + 2];
        NSRegularExpression *nonWords = [NSRegularExpression regularExpressionWithPattern:@"\\W" options:0 error:NULL];
        testNameComponent = [nonWords stringByReplacingMatchesInString:testNameComponent options:0 range:NSMakeRange(0, testNameComponent.length) withTemplate:@""];
        NSString *reportsDirPath = [NSString stringWithFormat:@"/%@/reports/", testNameComponent];
        reportsDir = [NSURL fileURLWithPath:reportsDirPath];
        fileManager = [[TestFileManager alloc] init];
        fileManager.workingDir = reportsDir.path;
        archiveFactory = mockProtocol(@protocol(DICEArchiveFactory));
        downloadManager = mock([DICEDownloadManager class]);
        importQueue = [[TestOperationQueue alloc] init];
        app = mock([UIApplication class]);
        backgroundTaskId = 0;
        backgroundTaskHandler = nil;
        [given([app beginBackgroundTaskWithName:@"dice.background_import" expirationHandler:anything()]) willDo:^id(NSInvocation *invocation) {
            if (backgroundTaskHandler != nil) {
                failure(@"attempted to begin background task with non-nil background task handler");
                return @(UIBackgroundTaskInvalid);
            }
            backgroundTaskHandler = invocation.mkt_arguments[1];
            backgroundTaskId += 1;
            return @(backgroundTaskId);
        }];
        [[givenVoid([app endBackgroundTask:0]) withMatcher:anything()] willDo:^id(NSInvocation *invocation) {
            NSUInteger endingTaskId = ((NSNumber *)invocation.mkt_arguments[0]).unsignedIntegerValue;
            if (endingTaskId != backgroundTaskId) {
                failure([NSString stringWithFormat:@"attempted to end background task with id %lu but outstanding task id was %lu", endingTaskId, backgroundTaskId]);
            }
            if (backgroundTaskHandler == nil) {
                failure([NSString stringWithFormat:@"attempted to end background task id %lu but handler is nil", backgroundTaskId]);
            }
            backgroundTaskHandler = nil;
            return nil;
        }];

        redType = [[TestReportType alloc] initWithExtension:@"red" fileManager:fileManager];
        blueType = [[TestReportType alloc] initWithExtension:@"blue" fileManager:fileManager];

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportTypes:@[redType, blueType]
            reportsDir:reportsDir
            exclusions:nil
            utiExpert:[[TestDICEUtiExpert alloc] init]
            archiveFactory:archiveFactory
            importQueue:importQueue
            fileManager:fileManager
            reportDb:reportDb
            application:app];
        store.downloadManager = downloadManager;
    });

    afterEach(^{
        [importQueue waitUntilAllOperationsAreFinished];
        stopMocking(archiveFactory);
        stopMocking(app);
        fileManager = nil;

        /*
         wait for all of MagicalRecord's NSManagedObjectContextDidSaveNotification handlers
         to finish processing before calling [MagicalRecord cleanUp].  these handlers 
         dispatch_async to the main thread to merge the notification changes from the root
         saving context to the default/main context.  if cleanup has already been called,
         the root context is nil, and when the notification handler tries to retrieve 
         the root context, [NSManagedObjectContext MR_rootSavingContext] throws an
         exception from a failed assertion that the root context is not nil.
         */
        NSURL *cleanupSourceFile = [NSURL fileURLWithPath:@"/MagicalRecord_cleanup"];
        [reportDb performBlock:^{
            Report *cleanupBarrier = [Report MR_createEntityInContext:reportDb];
            cleanupBarrier.sourceFile = cleanupSourceFile;
        }];
        waitUntil(^(DoneCallback done) {
            [reportDb observe:NSManagedObjectContextDidSaveNotification withBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [reportDb performBlock:^{
                        if ([[note insertedObjects] reportWithSourceUrl:cleanupSourceFile]) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                done();
                            });
                        };
                    }];
                });
            }];
            [reportDb performBlock:^{
                [reportDb save:NULL];
            }];
        });

        [reportDb clearNotificationObservers];
        [verifyDb clearNotificationObservers];
        [MagicalRecord cleanUp];
    });

    afterAll(^{
    });

    describe(@"state transitions", ^{

        it(@"transitions when next state does not equal current state", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test.red"];
            [fileManager setWorkingDirChildren:@"test.red", nil];
            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusNew;
            report.importStateToEnter = ReportImportStatusInspectingSourceFile;
            [verifyDb save:NULL];

            [store advancePendingImports];

            [reportDb waitForQueueToDrain];
            [verifyDb refreshObject:report mergeChanges:YES];

            expect(report.importState).to.equal(ReportImportStatusInspectingSourceFile);
            expect(report.uti).to.equal(UTI_RED);
        });

        it(@"does not transition when next state equals current state", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test.red"];
            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingSourceFile;
            report.importStateToEnter = ReportImportStatusInspectingSourceFile;
            [verifyDb save:NULL];

            [store advancePendingImports];

            [reportDb waitForQueueToDrain];
            [verifyDb refreshObject:report mergeChanges:YES];

            expect(report.importState).to.equal(ReportImportStatusInspectingSourceFile);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);
            expect(report.uti).to.beNil();
        });

    });

    describe(@"initial transition", ^{

        it(@"starts in new state to enter inspecting source file when source url is file", ^{

            [verifyResults performFetch:NULL];
            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red" isDirectory:NO];
            [fileManager setWorkingDirChildren:@"report.red", nil];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.lastObject;

            expect(report.title).to.equal(source.lastPathComponent);
            expect(report.summary).to.equal([NSString stringWithFormat:@"Added from file %@", report.dateAdded]);
            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);
        });

        it(@"starts in new state to enter downloading when source url starts with http", ^{

            [verifyResults performFetch:NULL];
            NSURL *source = [NSURL URLWithString:@"https://dice.com/test.zip"];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.lastObject;

            expect(report.title).to.equal(@"Downloading");
            expect(report.summary).to.equal([NSString stringWithFormat:@"Downloaded %@ from %@", report.dateAdded, report.remoteSource]);
            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusDownloading);
        });

        it(@"transitions from new to inspecting source file", ^{

            [verifyResults performFetch:NULL];
            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red" isDirectory:NO];
            [fileManager setWorkingDirChildren:@"report.red", nil];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.lastObject;

            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);

            [store advancePendingImports];

            expect(report.importState).to.equal(ReportImportStatusNew);

            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToInt(ReportImportStatusInspectingSourceFile));
        });
    });

    describe(@"importing stand-alone files from the documents directory", ^{

        it(@"transitions from inspecting source file to inspecting content", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red" isDirectory:NO];
            verifyResults.fetchRequest.predicate = [Report predicateForSourceUrl:source];
            [verifyResults performFetch:NULL];
            [fileManager setWorkingDirChildren:@"report.red", nil];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report.sourceFile).to.equal(source);
            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusInspectingContent));

            expect(report.importState).to.equal(ReportImportStatusInspectingSourceFile);
            expect(report.uti).to.equal(UTI_RED);
        });

        it(@"transitions from inspecting content to moving content", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red" isDirectory:NO];
            verifyResults.fetchRequest.predicate = [Report predicateForSourceUrl:source];
            [verifyResults performFetch:NULL];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingSourceFile;
            report.importStateToEnter = ReportImportStatusInspectingContent;
            report.uti = UTI_RED;

            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusMovingContent));

            expect(report.reportTypeId).to.equal(redType.reportTypeId);
            expect(report.importDir).to.equal([reportsDir URLByAppendingPathComponent:@"report.red.dice_import" isDirectory:YES]);
            expect(report.baseDirName).to.beNil();
            expect([fileManager isDirectoryAtUrl:report.importDir]).to.beTruthy();
        });

        it(@"transitions from moving content to digesting", ^{

            [fileManager setWorkingDirChildren:@"report.red", nil];
            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red" isDirectory:NO];
            verifyResults.fetchRequest.predicate = [Report predicateForSourceUrl:source];
            [verifyResults performFetch:NULL];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.importState = ReportImportStatusInspectingContent;
            report.importStateToEnter = ReportImportStatusMovingContent;
            report.sourceFile = source;
            report.uti = UTI_RED;
            report.reportTypeId = redType.reportTypeId;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"report.red.dice_import" isDirectory:YES];

            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            __block BOOL movedOnImportQueue = NO;
            __block NSString *movedSourceFileTo;
            fileManager.onMoveItemAtPath = ^BOOL(NSString * _Nonnull sourcePath, NSString * _Nonnull destPath, NSError *__autoreleasing  _Nullable * _Nullable error) {
                if ([sourcePath isEqualToString:source.path]) {
                    movedSourceFileTo = destPath;
                    movedOnImportQueue = NSOperationQueue.currentQueue == importQueue;
                }
                return YES;
            };

            [store advancePendingImports];

            assertWithTimeout(10.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusDigesting));

            [reportDb waitForQueueToDrain];

            expect(report.importState).to.equal(ReportImportStatusMovingContent);
            expect(report.importStateToEnter).to.equal(ReportImportStatusDigesting);
            expect(report.baseDirName).toNot.beNil();
            expect(report.rootFilePath).to.equal(@"report.red");
            expect([fileManager isDirectoryAtUrl:report.baseDir]).to.beTruthy();
            expect([fileManager isRegularFileAtUrl:report.rootFile]).to.beTruthy();
            expect(movedSourceFileTo).to.equal(report.rootFile.path);
            expect(movedOnImportQueue).to.beTruthy();
        });

        it(@"transitions from digesting to success", ^{

            [fileManager setWorkingDirChildren:@"report.red", nil];
            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red" isDirectory:NO];
            verifyResults.fetchRequest.predicate = [Report predicateForSourceUrl:source];
            [verifyResults performFetch:NULL];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusMovingContent;
            report.importStateToEnter = ReportImportStatusDigesting;
            report.uti = UTI_RED;
            report.reportTypeId = redType.reportTypeId;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"report.red.dice_import" isDirectory:YES];
            report.baseDirName = @"dice_content";
            report.rootFilePath = @"report.red";

            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            TestImportProcess *importProcess = [redType enqueueImport];
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusSuccess));

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusSuccess));

            Report *imported = [importProcess.report MR_inContext:verifyDb];

            expect(imported).to.equal(report);
            expect(importProcess.isFinished).to.beTruthy();
            expect(report.isImportFinished).to.beTruthy();
            expect(report.isEnabled).to.beTruthy();
        });

        it(@"imports a report successfully end to end", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red"];
            verifyResults.fetchRequest.predicate = [sourceUrlIsFinished predicateWithSubstitutionVariables:@{@"url": source}];
            [verifyResults performFetch:NULL];

            [store resumePendingImports];
            [fileManager setWorkingDirChildren:@"report.red", nil];
            [redType enqueueImport];
            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;
            expect(report).toNot.beNil();
            expect(report.isEnabled).to.beTruthy();
            expect(report.importState).to.equal(ReportImportStatusSuccess);
            expect(report.importStateToEnter).to.equal(report.importState);
            expect(report.rootFilePath).to.equal(@"report.red");
        });

        it(@"fails if the file does not exist", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test.red"];
            verifyResults.fetchRequest.predicate = [Report predicateForSourceUrl:source];
            [verifyResults performFetch:NULL];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report).notTo.beNil();
            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusFailed));

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(report.importState).to.equal(ReportImportStatusFailed);
            expect(report.isEnabled).to.beFalsy();
            expect(report.statusMessage).to.equal(@"Import failed");
            expect(report.summary).to.equal(@"File test.red does not exist");
        });

        it(@"fails if there is no applicable report type", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"unknown.green"];
            verifyResults.fetchRequest.predicate = [Report predicateForSourceUrl:source];
            [verifyResults performFetch:NULL];
            [fileManager setWorkingDirChildren:@"unknown.green", nil];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report).notTo.beNil();
            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusInspectingContent));

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusFailed));

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(report.importState).to.equal(ReportImportStatusFailed);
            expect(report.isEnabled).to.beFalsy();
            expect(report.statusMessage).to.equal(@"Import failed");
            expect(report.summary).to.equal(@"No supported content found");
        });

        it(@"fails if the source file was not moved", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test.red" isDirectory:NO];
            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.uti = UTI_RED;
            report.reportTypeId = redType.reportTypeId;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"test.red.dice_import" isDirectory:YES];
            report.importState = ReportImportStatusInspectingContent;
            report.importStateToEnter = ReportImportStatusMovingContent;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            [fileManager setWorkingDirChildren:@"test.red", @"test.red.dice_import/", nil];
            fileManager.onMoveItemAtPath = ^BOOL(NSString * _Nonnull sourcePath, NSString * _Nonnull destPath, NSError *__autoreleasing  _Nullable * _Nullable error) {
                *error = [NSError errorWithDomain:@"dice.test" code:357 userInfo:@{NSLocalizedDescriptionKey: @"doomed to failure"}];
                return NO;
            };

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusFailed));

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            expect(report.importState).to.equal(ReportImportStatusFailed);
            expect(report.isEnabled).to.beFalsy();
            expect(report.statusMessage).to.equal(@"Import failed");
            expect(report.summary).to.equal(@"Error moving content to import directory: doomed to failure");
        });

        it(@"does not start a new import for a file already importing", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test.red"];
            [verifyResults performFetch:NULL];
            [fileManager setWorkingDirChildren:@"test.red", nil];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);

            [store attemptToImportReportFromResource:source];
            [store advancePendingImports];
            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(1);
            expect(verifyResults.fetchedObjects.firstObject).to.equal(report);

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusInspectingContent));

            [store advancePendingImports];
            [store attemptToImportReportFromResource:source];
            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusMovingContent));

            expect(verifyResults.fetchedObjects).to.haveCountOf(1);
            expect(verifyResults.fetchedObjects.firstObject).to.equal(report);
        });

        it(@"does not start a new import for a file already imported", ^{
            failure(@"todo: if file is already imported and source file exists, prompt to overwrite or import as new");
        });

        it(@"can retry a failed import after deleting the report", ^{

            failure(@"todo");

//            NSURL *url = [reportsDir URLByAppendingPathComponent:@"oops.bloo"];
//            [fileManager setWorkingDirChildren:url.lastPathComponent, nil];
//            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            NSNotification *note = obs.received.firstObject.notification;
//
//            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//
//            [store deleteReport:report];
//
//            assertWithTimeout(1.0, thatEventually(store.reports), isNot(contains(report, nil)));
//
//            [fileManager setWorkingDirChildren:url.lastPathComponent, nil];
//
//            Report *retry = [store attemptToImportReportFromResource:url];
//
//            expect(retry).toNot.beIdenticalTo(report);
//
//            assertWithTimeout(1.0, thatEventually(@(retry.isImportFinished)), isTrue());
//
//            expect(retry.importState).to.equal(ReportImportStatusFailed);
//            expect(obs.received).to.haveCountOf(2);
//            expect(obs.received[0].notification.userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(obs.received[1].notification.userInfo[@"report"]).to.beIdenticalTo(retry);
        });

        xit(@"passees the content match predicate to the import process", ^{
            /*
             TODO: Allow the ReportContentMatchPredicate to pass information to
             the ImportProcess about what was found in the archive.  this will
             help support alternatives to the standard index.html assumption by
             potentially allowing the ImportProcess to rename or symlink html
             resources found during the archive entry enumeration.
             Also the HtmlReportType should do a breadth first search for html
             files, or at least in the base dir.  also maybe restore the fail-
             fast element of the ReportTypeMatchPredicate, e.g., if index.html
             exists at the root, stop immediately.  Possibly reuse the ReportContentMatchPredicate
             for enumerating file system contents.
             */
            failure(@"do it");
        });

    });

    describe(@"importing directories from the documents directory", ^{

        it(@"ignores import directories", ^{

            [verifyResults performFetch:NULL];
            NSURL *importDirSource = [reportsDir URLByAppendingPathComponent:@"ignore.dice_import" isDirectory:YES];
            [fileManager setWorkingDirChildren:@"ignore.dice_import/blue_content/index.blue", nil];
            [store attemptToImportReportFromResource:importDirSource];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(0);

            NSURL *otherSource = [reportsDir URLByAppendingPathComponent:@"import_me" isDirectory:YES];
            [fileManager createFilePath:@"import_me/" contents:nil];
            [store attemptToImportReportFromResource:otherSource];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(1);
            Report *report = verifyResults.fetchedObjects.firstObject;
            expect(report.sourceFile).to.equal(otherSource);
        });

        it(@"transitions from new to inspecting source file", ^{

            [verifyResults performFetch:NULL];
            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test_report" isDirectory:YES];
            [fileManager setWorkingDirChildren:@"test_report/", nil];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report.sourceFile).to.equal(source);
            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusInspectingContent));

            expect(report.uti).to.beNil();
        });

        it(@"transitions from inspecting content to moving content", ^{

            [verifyResults performFetch:NULL];
            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test_report" isDirectory:YES];
            [fileManager setWorkingDirChildren:@"test_report/index.blue", nil];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingSourceFile;
            report.importStateToEnter = ReportImportStatusInspectingContent;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"test_report.dice_import" isDirectory:YES];
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusMovingContent));

            expect(report.reportTypeId).to.equal(blueType.reportTypeId);
        });

        it(@"transitions from moving content to digesting", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test_report" isDirectory:YES];
            [fileManager setWorkingDirChildren:@"test_report/index.blue", nil];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingContent;
            report.importStateToEnter = ReportImportStatusMovingContent;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"test_report.dice_import" isDirectory:YES];
            report.reportTypeId = redType.reportTypeId;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            __block BOOL movedSourceFileOnImportQueue = NO;
            NSString *baseDirPath = [report.importDir.path stringByAppendingPathComponent:@"test_report"];
            fileManager.onMoveItemAtPath = ^BOOL(NSString * _Nonnull sourcePath, NSString * _Nonnull destPath, NSError *__autoreleasing  _Nullable * _Nullable error) {
                if ([sourcePath isEqualToString:source.path] && [destPath isEqualToString:baseDirPath]) {
                    movedSourceFileOnImportQueue = NSOperationQueue.currentQueue == importQueue;
                }
                return YES;
            };

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusDigesting));

            expect(report.importState).to.equal(ReportImportStatusMovingContent);
            expect(report.baseDirName).to.equal(@"test_report");
            expect(report.rootFilePath).to.beNil();
            expect(movedSourceFileOnImportQueue).to.beTruthy();
            expect([fileManager fileExistsAtPath:report.sourceFile.path]).to.beFalsy();
            expect([fileManager isDirectoryAtUrl:report.baseDir]).to.beTruthy();
        });

        it(@"transitions from digesting to success", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test_report" isDirectory:YES];
            [fileManager setWorkingDirChildren:@"test_report.dice_import/test_report/index.blue", nil];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusMovingContent;
            report.importStateToEnter = ReportImportStatusDigesting;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"test_report.dice_import" isDirectory:YES];
            report.reportTypeId = blueType.reportTypeId;
            report.baseDirName = @"test_report";
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            TestImportProcess *importProcess = [blueType enqueueImport];
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusSuccess));

            expect(report.importState).to.equal(ReportImportStatusDigesting);
            expect(report.rootFilePath).to.equal(@"index.blue");
            expect(report.uti).to.equal(UTI_BLUE);
            expect(importProcess.isFinished).to.beTruthy();
            expect(importProcess.wasSuccessful).to.beTruthy();
            Report *imported = [importProcess.report MR_inContext:verifyDb];
            expect(imported).to.equal(report);
        });

        it(@"parses the report descriptor if present in base dir as metadata.json", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [fileManager setWorkingDirChildren:@"blue_base.dice_import/blue_base/index.blue", nil];
            NSString *jsonDescriptor = @"{\"title\": \"Title From Descriptor\", \"description\": \"Summary from descriptor\"}";
            [fileManager createFilePath:@"blue_base.dice_import/blue_base/metadata.json" contents:[jsonDescriptor dataUsingEncoding:NSUTF8StringEncoding]];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusMovingContent;
            report.importStateToEnter = ReportImportStatusDigesting;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"blue_base.dice_import" isDirectory:YES];
            report.reportTypeId = blueType.reportTypeId;
            report.baseDirName = @"blue_base";
            report.title = source.lastPathComponent;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            [blueType enqueueImport];
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusSuccess));

            expect(report.title).to.equal(@"Title From Descriptor");
            expect(report.summary).to.equal(@"Summary from descriptor");
        });

        it(@"parses the report descriptor if present in base dir as dice.json", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [fileManager setWorkingDirChildren:@"blue_base.dice_import/blue_base/index.blue", nil];
            NSString *jsonDescriptor = @"{\"title\": \"Title From Descriptor\", \"description\": \"Summary from descriptor\"}";
            [fileManager createFilePath:@"blue_base.dice_import/blue_base/dice.json" contents:[jsonDescriptor dataUsingEncoding:NSUTF8StringEncoding]];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusMovingContent;
            report.importStateToEnter = ReportImportStatusDigesting;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"blue_base.dice_import" isDirectory:YES];
            report.reportTypeId = blueType.reportTypeId;
            report.baseDirName = @"blue_base";
            report.title = source.lastPathComponent;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            [blueType enqueueImport];
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusSuccess));

            expect(report.title).to.equal(@"Title From Descriptor");
            expect(report.summary).to.equal(@"Summary from descriptor");
        });

        it(@"prefers dice.json to metadata.json", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
            [fileManager setWorkingDirChildren:@"blue_base.dice_import/blue_base/index.blue", nil];
            [fileManager createFilePath:@"blue_base.dice_import/blue_base/dice.json" contents:
                [@"{\"title\": \"Title From dice.json\", \"description\": \"Summary from dice.json\"}"
                    dataUsingEncoding:NSUTF8StringEncoding]];
            [fileManager createFilePath:@"blue_base.dice_import/blue_base/metadata.json" contents:
                [@"{\"title\": \"Title From metadata.json\", \"description\": \"Summary from metadata.json\"}"
                    dataUsingEncoding:NSUTF8StringEncoding]];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusMovingContent;
            report.importStateToEnter = ReportImportStatusDigesting;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"blue_base.dice_import" isDirectory:YES];
            report.reportTypeId = blueType.reportTypeId;
            report.baseDirName = @"blue_base";
            report.title = source.lastPathComponent;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            [blueType enqueueImport];
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToInt(ReportImportStatusSuccess));

            expect(report.title).to.equal(@"Title From dice.json");
            expect(report.summary).to.equal(@"Summary from dice.json");
        });

        it(@"creates import dir and record for downloads on first progress update", ^{

            failure(@"todo");

//            NSURL *downloadUrl = [NSURL URLWithString:@"http://dice.com/persist-me"];
//            Report *report = [store attemptToImportReportFromResource:downloadUrl];
//
//            expect(report.remoteSource).to.equal(downloadUrl);
//            expect(report.importDir).to.beNil();
//
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:report.remoteSource];
//            download.bytesExpected = 123456789;
//            download.bytesReceived = 12345678;
//            download.fileName = @"persist-me.zip";
//
//            [store downloadManager:downloadManager didReceiveDataForDownload:download];
//
//            expect(report.importDir).toNot.beNil();
//            expect([fileManager isDirectoryAtUrl:report.importDir]).to.beTruthy();
//            expect([fileManager isRegularFileAtUrl:[report.importDir URLByAppendingPathComponent:@"dice.obj"]]).to.beTruthy();
//
//            NSData *record = [fileManager contentsAtPath:[report.importDir.path stringByAppendingPathComponent:@"dice.obj"]];
//            NSKeyedUnarchiver *coder = [[NSKeyedUnarchiver alloc] initForReadingWithData:record];
//            Report *loaded = [[Report alloc] initWithCoder:coder];
//            [coder finishDecoding];
//
//            expect(loaded.remoteSource).to.equal(downloadUrl);
//            expect(loaded.importDir).to.equal(report.importDir);
//            expect(loaded.importState).to.equal(ReportImportStatusDownloading);
        });

        it(@"creates import dir and record for downloads on completion", ^{

            failure(@"todo");

//            NSURL *downloadUrl = [NSURL URLWithString:@"http://dice.com/persist-me"];
//            Report *report = [store attemptToImportReportFromResource:downloadUrl];
//
//            expect(report.remoteSource).to.equal(downloadUrl);
//            expect(report.importDir).to.beNil();
//
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:report.remoteSource];
//            download.bytesExpected = 123456789;
//            download.bytesReceived = 12345678;
//            download.fileName = @"persist-me.zip";
//
//            NSURL *downloadFile = [reportsDir URLByAppendingPathComponent:download.fileName];
//            [store downloadManager:downloadManager willFinishDownload:download movingToFile:downloadFile];
//            download.downloadedFile = downloadFile;
//            [store downloadManager:downloadManager didFinishDownload:download];
//
//            expect(report.importDir).toNot.beNil();
//            expect([fileManager isDirectoryAtUrl:report.importDir]).to.beTruthy();
//            expect([fileManager isRegularFileAtUrl:[report.importDir URLByAppendingPathComponent:@"dice.obj"]]).to.beTruthy();
//
//            NSData *record = [fileManager contentsAtPath:[report.importDir.path stringByAppendingPathComponent:@"dice.obj"]];
//            NSKeyedUnarchiver *coder = [[NSKeyedUnarchiver alloc] initForReadingWithData:record];
//            Report *loaded = [[Report alloc] initWithCoder:coder];
//            [coder finishDecoding];
//
//            expect(loaded.remoteSource).to.equal(downloadUrl);
//            expect(loaded.importDir).to.equal(report.importDir);
//            expect(loaded.sourceFile).to.equal(downloadFile);
//            expect(loaded.importState).to.equal(ReportImportStatusNewLocal);
        });
    });

    // #pragma mark - Importing archives

    describe(@"importing report archives from the documents directory", ^{

        it(@"transitions from inspecting source file to inspecting archive", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"test.zip" isDirectory:NO];
            verifyResults.fetchRequest.predicate = [Report predicateForSourceUrl:source];
            [verifyResults performFetch:NULL];
            [fileManager setWorkingDirChildren:@"test.zip", nil];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToInt(ReportImportStatusInspectingArchive));

            expect(report.uti).to.equal((__bridge NSString *)kUTTypeZipArchive);
        });

        it(@"transitions from inspecting archive to extracting", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            [fileManager setWorkingDirChildren:@"blue.zip", nil];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:source archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:source withUti:kUTTypeZipArchive]) willReturn:archive];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingSourceFile;
            report.importStateToEnter = ReportImportStatusInspectingArchive;
            report.uti = (__bridge NSString *)kUTTypeZipArchive;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToInt(ReportImportStatusExtractingContent));

            expect(report.importDir).to.equal([reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES]);
            expect(report.baseDirName).to.equal(@"blue_base");
            expect(report.reportTypeId).to.equal(blueType.reportTypeId);
            expect([fileManager isDirectoryAtUrl:report.importDir]).to.beTruthy();
            expect([fileManager isDirectoryAtUrl:report.baseDir]).to.beFalsy();
        });

        it(@"transitions from extracting content to digesting", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            [fileManager setWorkingDirChildren:@"blue.zip", nil];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:source archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:source withUti:kUTTypeZipArchive]) willReturn:archive];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingArchive;
            report.importStateToEnter = ReportImportStatusExtractingContent;
            report.uti = (__bridge NSString *)kUTTypeZipArchive;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
            report.baseDirName = @"blue_base";
            report.reportTypeId = blueType.reportTypeId;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            __block DICEExtractReportOperation *extractOp;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:DICEExtractReportOperation.class]) {
                    extractOp = (DICEExtractReportOperation *)op;
                }
            };

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];
            
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToInt(ReportImportStatusDigesting));

            expect([fileManager isDirectoryAtUrl:report.baseDir]);
            expect([fileManager isRegularFileAtUrl:[report.baseDir URLByAppendingPathComponent:@"index.blue"]]).to.beTruthy();
            expect(extractOp).toNot.beNil();
            expect(extractOp.archive.archiveUrl).to.equal(source);
            expect(extractOp.destDir).to.equal(report.importDir);
            Report *extractedReport = [extractOp.report MR_inContext:verifyDb];
            expect(extractedReport).to.equal(report);

            [NSFileHandle deswizzleAllMethods];
        });

        it(@"creates a base dir if the archive has no base dir", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            [fileManager setWorkingDirChildren:@"blue.zip", nil];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"images/thumb.png" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:source archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:source withUti:kUTTypeZipArchive]) willReturn:archive];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingArchive;
            report.importStateToEnter = ReportImportStatusExtractingContent;
            report.uti = (__bridge NSString *)kUTTypeZipArchive;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import"];
            report.baseDirName = nil;
            report.reportTypeId = blueType.reportTypeId;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            __block DICEExtractReportOperation *extractOp;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:DICEExtractReportOperation.class]) {
                    extractOp = (DICEExtractReportOperation *)op;
                }
            };

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToInt(ReportImportStatusDigesting));

            expect(report.baseDirName).to.equal(@"dice_content");
            expect([fileManager isDirectoryAtUrl:report.importDir]).to.beTruthy();
            expect([fileManager isDirectoryAtUrl:report.baseDir]).to.beTruthy();
            expect(extractOp).toNot.beNil();
            expect(extractOp.archive.archiveUrl).to.equal(source);
            expect(extractOp.destDir).to.equal(report.baseDir);
            Report *extractedReport = [extractOp.report MR_inContext:verifyDb];
            expect(extractedReport).to.equal(report);

            [NSFileHandle deswizzleAllMethods];
        });

        it(@"deletes the archive file after extracting the contents", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            [fileManager setWorkingDirChildren:@"blue.zip", nil];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:source archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:source withUti:kUTTypeZipArchive]) willReturn:archive];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingArchive;
            report.importStateToEnter = ReportImportStatusExtractingContent;
            report.uti = (__bridge NSString *)kUTTypeZipArchive;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
            report.baseDirName = @"blue_base";
            report.reportTypeId = blueType.reportTypeId;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            __block DeleteFileOperation *deleteArchive;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:DeleteFileOperation.class]) {
                    deleteArchive = (DeleteFileOperation *)op;
                }
            };

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];
            
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusDigesting));

            expect(deleteArchive).toNot.beNil();

            assertWithTimeout(1.0, thatEventually(@(deleteArchive.isFinished)), isTrue());

            expect([fileManager isRegularFileAtUrl:source]).to.beFalsy();
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not delete the archive file if the extract fails", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            [fileManager setWorkingDirChildren:@"blue.zip", nil];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:source archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:source withUti:kUTTypeZipArchive]) willReturn:archive];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = source;
            report.importState = ReportImportStatusInspectingArchive;
            report.importStateToEnter = ReportImportStatusExtractingContent;
            report.uti = (__bridge NSString *)kUTTypeZipArchive;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
            report.baseDirName = @"blue_base";
            report.reportTypeId = blueType.reportTypeId;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            __block DeleteFileOperation *deleteArchive;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:DeleteFileOperation.class]) {
                    deleteArchive = (DeleteFileOperation *)op;
                }
            };

            __block NSError *fileHandleError = [NSError errorWithDomain:@"DICETest" code:999 userInfo:nil];
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    *errOut = fileHandleError;
                    return nil;
                };
            }];
            
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusFailed));

            expect(deleteArchive).to.beNil();
            expect([fileManager isRegularFileAtUrl:source]).to.beTruthy();
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"updates extract progress", ^{

            [fileManager setWorkingDirChildren:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:(1 << 20)]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            NSMutableArray<NSNumber *> *percents = [NSMutableArray array];
            [reportDb observe:NSManagedObjectContextWillSaveNotification withBlock:^(NSNotification *note) {
                Report *extracting = [reportDb.updatedObjects reportWithSourceUrl:archiveUrl];
                if (extracting == nil) {
                    return;
                }
                NSNumber *oldPercent = extracting.changedValues[@"extractPercent"];
                if (oldPercent) {
                    [percents addObject:oldPercent];
                }
            }];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.sourceFile = archiveUrl;
            report.importState = ReportImportStatusInspectingArchive;
            report.importStateToEnter = ReportImportStatusExtractingContent;
            report.uti = (__bridge NSString *)kUTTypeZipArchive;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import"];
            report.baseDirName = nil;
            report.reportTypeId = blueType.reportTypeId;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            [store advancePendingImports ];

            assertWithTimeout(2.0, thatEventually(@(report.importStateToEnter)), equalToInt(ReportImportStatusDigesting));

            assertThat(percents, hasCount(greaterThan(@10)));
            expect(percents.lastObject).to.equal(@100);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"load reports does not create multiple reports while the archive is extracting", ^{

            [verifyResults performFetch:NULL];

            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            [fileManager setWorkingDirChildren:archiveUrl.lastPathComponent, nil];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DICEExtractReportOperation *extract = nil;
            __block BOOL multipleExtracts = NO;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        multipleExtracts = YES;
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [extract block];
                }
            };

            [store resumePendingImports];
            [store loadContentFromReportsDir:nil];

            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());

            __block BOOL moreInserted = NO;
            __block BOOL importRestarted = NO;
            [reportDb observe:NSManagedObjectContextWillSaveNotification withBlock:^(NSNotification *note) {
                moreInserted = reportDb.insertedObjects.count > 0;
                Report *updated = [reportDb.updatedObjects reportWithSourceUrl:archiveUrl];
                if (updated) {
                    if (updated.changedValues[@"importState"]) {
                        importRestarted = updated.importState < ReportImportStatusExtractingContent;
                    }
                }
            }];

            expect(verifyResults.fetchedObjects).to.haveCountOf(1);

            [store loadContentFromReportsDir:nil];
            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(1);
            expect(moreInserted).to.beFalsy();
            expect(importRestarted).to.beFalsy();

            [blueType enqueueImport];
            [extract unblock];

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report.sourceFile).to.equal(archiveUrl);

            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(moreInserted).to.beFalsy();
            expect(importRestarted).to.beFalsy();
            expect(multipleExtracts).to.beFalsy();
            expect(verifyResults.fetchedObjects).to.haveCountOf(1);
            expect(report.importState).to.equal(ReportImportStatusSuccess);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"single import does not create multiple reports while the archive is extracting", ^{

            [verifyResults performFetch:NULL];

            [fileManager setWorkingDirChildren:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            __block DICEExtractReportOperation *extract;
            __block BOOL multipleExtracts = NO;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        multipleExtracts = YES;
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [extract block];
                }
            };

            [store resumePendingImports];
            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());

            expect(verifyResults.fetchedObjects).to.haveCountOf(1);

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report.sourceFile).to.equal(archiveUrl);

            __block BOOL moreInserted = NO;
            __block BOOL importRestarted = NO;
            [reportDb observe:NSManagedObjectContextWillSaveNotification withBlock:^(NSNotification *note) {
                moreInserted = reportDb.insertedObjects.count > 0;
                Report *updated = [reportDb.updatedObjects reportWithSourceUrl:archiveUrl];
                if (updated) {
                    if (updated.changedValues[@"importState"]) {
                        importRestarted = updated.importState < ReportImportStatusExtractingContent;
                    }
                }
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(1);
            expect(report.importState).to.equal(ReportImportStatusExtractingContent);

            [blueType enqueueImport];
            [extract unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(moreInserted).to.beFalsy();
            expect(importRestarted).to.beFalsy();
            expect(multipleExtracts).to.beFalsy();
            expect(verifyResults.fetchedObjects).to.haveCountOf(1);
            expect(report.importState).to.equal(ReportImportStatusSuccess);

            [NSFileHandle deswizzleAllClassMethods];
        });
    });

    describe(@"load all reports", ^{

        it(@"creates reports for each file in reports directory", ^{

            [verifyResults performFetch:NULL];
            [fileManager setWorkingDirChildren:@"report1.red", @"report2.blue", @"something.else", nil];

            [store loadContentFromReportsDir:nil];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(3);

            assertThat(verifyResults.fetchedObjects, hasItems(
                hasProperty(@"sourceFile", [reportsDir URLByAppendingPathComponent:@"report1.red"]),
                hasProperty(@"sourceFile", [reportsDir URLByAppendingPathComponent:@"report2.blue"]),
                hasProperty(@"sourceFile", [reportsDir URLByAppendingPathComponent:@"something.else"]),
                nil));
        });

        it(@"updates status of reports whose content has been deleted", ^{

            [verifyResults performFetch:NULL];

            Report *report1 = [Report MR_createEntityInContext:verifyDb];
            report1.sourceFile = [reportsDir URLByAppendingPathComponent:@"report1.red"];
            report1.importDir = [reportsDir URLByAppendingPathComponent:@"report1.red.dice_import"];
            report1.baseDirName = @"dice_content";
            report1.rootFilePath = @"report1.red";
            report1.uti = UTI_RED;
            report1.importState = report1.importStateToEnter = ReportImportStatusSuccess;
            report1.statusMessage = @"Import complete";
            report1.isEnabled = YES;

            Report *report2 = [Report MR_createEntityInContext:verifyDb];
            report2.sourceFile = [reportsDir URLByAppendingPathComponent:@"report2.red"];
            report2.importDir = [reportsDir URLByAppendingPathComponent:@"report2.red.dice_import"];
            report2.baseDirName = @"dice_content";
            report2.rootFilePath = @"report2.red";
            report2.uti = UTI_RED;
            report2.importState = report2.importStateToEnter = ReportImportStatusSuccess;
            report2.statusMessage = @"Import complete";
            report2.isEnabled = YES;

            Report *report3 = [Report MR_createEntityInContext:verifyDb];
            report3.sourceFile = [reportsDir URLByAppendingPathComponent:@"report3.red"];
            report3.importDir = [reportsDir URLByAppendingPathComponent:@"report3.red.dice_import"];
            report3.baseDirName = @"dice_content";
            report3.rootFilePath = @"report3.red";
            report3.uti = UTI_RED;
            report3.importState = report3.importStateToEnter = ReportImportStatusSuccess;
            report3.statusMessage = @"Import complete";
            report3.isEnabled = YES;

            [verifyDb MR_saveToPersistentStoreAndWait];
            [report1 willAccessValueForKey:nil];
            [report2 willAccessValueForKey:nil];
            [report3 willAccessValueForKey:nil];

            [fileManager setWorkingDirChildren:report1.rootFile.path, report2.rootFile.path, report3.rootFile.path, nil];
            [store loadContentFromReportsDir:nil];
            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(3);
            expect(report1.importState).to.equal(ReportImportStatusSuccess);
            expect(report1.isEnabled).to.beTruthy();
            expect(report2.importState).to.equal(ReportImportStatusSuccess);
            expect(report2.isEnabled).to.beTruthy();
            expect(report3.importState).to.equal(ReportImportStatusSuccess);
            expect(report3.isEnabled).to.beTruthy();

            [fileManager removeItemAtURL:report1.importDir error:nil];
            [store loadContentFromReportsDir:nil];
            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(3);
            expect(report1.importState).to.equal(ReportImportStatusFailed);
            expect(report1.importStateToEnter).to.equal(ReportImportStatusFailed);
            expect(report1.statusMessage).to.equal(@"Main resource does not exist: report1.red.dice_import/dice_content/report1.red");
            expect(report1.isEnabled).to.beFalsy();
            expect(report2.importState).to.equal(ReportImportStatusSuccess);
            expect(report2.isEnabled).to.beTruthy();
            expect(report3.importState).to.equal(ReportImportStatusSuccess);
            expect(report3.isEnabled).to.beTruthy();

            [fileManager removeItemAtURL:report2.baseDir error:NULL];
            [store loadContentFromReportsDir:nil];
            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(3);
            expect(report1.importState).to.equal(ReportImportStatusFailed);
            expect(report1.importStateToEnter).to.equal(ReportImportStatusFailed);
            expect(report1.statusMessage).to.equal(@"Main resource does not exist: report1.red.dice_import/dice_content/report1.red");
            expect(report1.isEnabled).to.beFalsy();
            expect(report2.importState).to.equal(ReportImportStatusFailed);
            expect(report2.importStateToEnter).to.equal(ReportImportStatusFailed);
            expect(report2.statusMessage).to.equal(@"Main resource does not exist: report2.red.dice_import/dice_content/report2.red");
            expect(report2.isEnabled).to.beFalsy();
            expect(report3.importState).to.equal(ReportImportStatusSuccess);
            expect(report3.isEnabled).to.beTruthy();

            [fileManager removeItemAtURL:report3.importDir error:NULL];
            [store loadContentFromReportsDir:nil];
            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(3);
            expect(report1.importState).to.equal(ReportImportStatusFailed);
            expect(report1.importStateToEnter).to.equal(ReportImportStatusFailed);
            expect(report1.statusMessage).to.equal(@"Main resource does not exist: report1.red.dice_import/dice_content/report1.red");
            expect(report1.isEnabled).to.beFalsy();
            expect(report2.importState).to.equal(ReportImportStatusFailed);
            expect(report2.importStateToEnter).to.equal(ReportImportStatusFailed);
            expect(report2.statusMessage).to.equal(@"Main resource does not exist: report2.red.dice_import/dice_content/report2.red");
            expect(report2.isEnabled).to.beFalsy();
            expect(report3.importState).to.equal(ReportImportStatusFailed);
            expect(report3.importStateToEnter).to.equal(ReportImportStatusFailed);
            expect(report3.statusMessage).to.equal(@"Main resource does not exist: report3.red.dice_import/dice_content/report3.red");
            expect(report3.isEnabled).to.beFalsy();
        });

        it(@"saves and calls completion block only once for the entire load operation", ^{

            Report *defunct = [Report MR_createEntityInContext:verifyDb];
            defunct.sourceFile = [reportsDir URLByAppendingPathComponent:@"defunct.red"];
            defunct.importDir = [reportsDir URLByAppendingPathComponent:@"defunct.red.dice_import"];
            defunct.baseDirName = @"dice_content";
            defunct.rootFilePath = @"defunct.red";
            defunct.uti = UTI_RED;
            defunct.importState = defunct.importStateToEnter = ReportImportStatusSuccess;
            defunct.statusMessage = @"Import complete";
            defunct.isEnabled = YES;
            [verifyDb save:NULL];

            [verifyDb waitForQueueToDrain];
            [reportDb waitForQueueToDrain];

            NSMutableArray<NSNotification *> *saves = [NSMutableArray array];
            [reportDb observe:NSManagedObjectContextDidSaveNotification withBlock:^(NSNotification *note) {
                [saves addObject:note];
            }];

            [verifyResults performFetch:NULL];
            [fileManager setWorkingDirChildren:@"report1.red", @"report2.red", @"report3.red", nil];
            __block NSUInteger completed = 0;
            [store loadContentFromReportsDir:^{
                completed += 1;
            }];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(4);
            expect(saves.count).to.equal(1);
            expect(completed).to.equal(1);
        });
    });

    describe(@"autonomous operation", ^{

        it(@"advances when a state change occurs", ^{
            failure(@"todo");
        });

        it(@"does not advance if a save occurs without changing import state", ^{
            failure(@"todo");
        });
    });

#pragma mark - Downloading

    describe(@"downloading content", ^{

        it(@"starts a download when entering the downloading state", ^{

            [verifyResults performFetch:NULL];
            NSURL *remoteSource = [NSURL URLWithString:@"https://dice.com/report"];
            [store attemptToImportReportFromResource:remoteSource];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(1);
            Report *report = verifyResults.fetchedObjects.firstObject;
            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusDownloading);

            [store advancePendingImports];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(report.importState).to.equal(ReportImportStatusDownloading);
            expect(report.importStateToEnter).to.equal(ReportImportStatusDownloading);

            [verify(downloadManager) downloadUrl:remoteSource];
        });

        it(@"updates download progress", ^{

            NSURL *remoteSource = [NSURL URLWithString:@"http://dice.com/test"];
            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.remoteSource = remoteSource;
            report.importStateToEnter = report.importState = ReportImportStatusDownloading;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            DICEDownload *download = [[DICEDownload alloc] initWithUrl:remoteSource];
            download.bytesExpected = 999999;
            download.bytesReceived = 33333;
            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(report.downloadSize).to.equal(999999);
            expect(report.downloadProgress).to.equal(33333);
            expect(report.downloadPercent).to.equal(3);
        });

        it(@"only saves progress updates at intervals of 750KB after initial udpate", ^{

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.remoteSource = [NSURL URLWithString:@"http://dice.com/test/progress"];
            report.importStateToEnter = report.importState = ReportImportStatusDownloading;

            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            DICEDownload *download = [[DICEDownload alloc] initWithUrl:report.remoteSource];
            download.bytesExpected = 1000000;
            download.bytesReceived = 100000;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(report.downloadProgress).to.equal(100000);

            download.bytesReceived += 250000;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(report.downloadProgress).to.equal(100000);

            download.bytesReceived += 500000;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(report.downloadProgress).to.equal(850000);
        });

        it(@"only saves download progress when the download percent changes when the download size is larger than 75000000", ^{

            [verifyResults performFetch:NULL];
            
            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.remoteSource = [NSURL URLWithString:@"http://dice.com/test/progress"];
            report.importStateToEnter = report.importState = ReportImportStatusDownloading;

            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            DICEDownload *download = [[DICEDownload alloc] initWithUrl:report.remoteSource];
            download.bytesExpected = 100000000;
            download.bytesReceived = 100000;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(report.downloadProgress).to.equal(0);
            expect(report.downloadPercent).to.equal(0);

            download.bytesReceived += 750000;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(report.downloadProgress).to.equal(0);
            expect(report.downloadPercent).to.equal(0);

            download.bytesReceived += 150000;
            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(report.downloadProgress).to.equal(1000000);
            expect(report.downloadPercent).to.equal(1);
        });

        it(@"ignores download messages about a url that does not match a report", ^{

            [verifyResults performFetch:NULL];

            DICEDownload *download = [[DICEDownload alloc] initWithUrl:[NSURL URLWithString:@"http://dice.com/mystery"]];
            download.bytesExpected = 123456789;
            download.bytesReceived = 123456000;

            [store downloadManager:downloadManager didReceiveDataForDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(0);

            download.bytesReceived = download.bytesExpected;
            NSURL *file = [reportsDir URLByAppendingPathComponent:@"mystery.zip"];
            [store downloadManager:downloadManager willFinishDownload:download movingToFile:file];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(0);

            download.fileName = file.lastPathComponent;
            download.downloadedFile = file;
            [store downloadManager:downloadManager didFinishDownload:download];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            expect(verifyResults.fetchedObjects).to.haveCountOf(0);
        });

        it(@"transitions from downloading to inspecting source file", ^{

            NSURL *remoteSource = [NSURL URLWithString:@"http://dice.com/report.blue"];
            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.remoteSource = remoteSource;
            report.importState = report.importStateToEnter = ReportImportStatusDownloading;

            [verifyDb MR_saveToPersistentStoreAndWait];
            [report willAccessValueForKey:nil];

            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"report.blue" isDirectory:NO];
            DICEDownload *download = [[DICEDownload alloc] initWithUrl:remoteSource];
            download.bytesReceived = download.bytesExpected = 9999999;
            download.fileName = sourceFile.lastPathComponent;

            [store downloadManager:downloadManager willFinishDownload:download movingToFile:sourceFile];

            [reportDb waitForQueueToDrain];
            [verifyDb waitForQueueToDrain];

            NSURL *reportSourceFile = report.sourceFile;
            expect(reportSourceFile).to.equal(sourceFile);

            download.wasSuccessful = YES;
            download.downloadedFile = sourceFile;

            [store downloadManager:store.downloadManager didFinishDownload:download];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToInt(ReportImportStatusInspectingSourceFile));
        });

        it(@"responds to failed downloads", ^{

            failure(@"todo");

//            TestImportProcess *import = [blueType enqueueImport];
//            import.steps = @[[NSBlockOperation blockOperationWithBlock:^{
//                failure(@"erroneously started import process for failed download");
//            }]];
//            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:store.notifications from:store withBlock:nil];
//            [obs observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            download.bytesReceived = 0;
//            download.downloadedFile = nil;
//            download.wasSuccessful = NO;
//            download.httpResponseCode = 503;
//
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            [store downloadManager:store.downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(obs.received.lastObject.notification.name), equalTo(ReportNotification.reportImportFinished));
//
//            expect(obs.received).to.haveCountOf(1);
//            expect(obs.received.lastObject.notification.name).to.equal(ReportNotification.reportImportFinished);
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//            expect(report.isEnabled).to.beFalsy();
        });

        it(@"can import a downloaded archive file", ^{

            failure(@"todo");

//            NSURL *downloadUrl = [NSURL URLWithString:@"http://dice.com/report.zip"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:downloadUrl];
//            download.bytesExpected = 999999;
//            Report *report = [store attemptToImportReportFromResource:downloadUrl];
//            download.bytesReceived = 555555;
//            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];
//            download.bytesReceived = 999999;
//            NSURL *downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.zip"];
//            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:downloadedFile];
//            [fileManager createFileAtPath:downloadUrl.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
//            download.wasSuccessful = YES;
//            download.downloadedFile = downloadedFile;
//            download.mimeType = @"application/zip";
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:999999 sizeExtracted:999999]
//            ] archiveUrl:downloadedFile archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:downloadedFile withUti:kUTTypeZipArchive]) willReturn:archive];
//            NSFileHandle *handle = mock([NSFileHandle class]);
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return handle;
//                };
//            }];
//            TestImportProcess *blueImport = [blueType enqueueImport];
//
//            [store downloadManager:store.downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isImportFinished)), isTrue());
//
//            expect(report.importState).to.equal(ReportImportStatusSuccess);
//
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"can re-download the same url after failing to import a downloaded file", ^{

            failure(@"todo");

//            TestImportProcess *importProcess = [blueType enqueueImport];
//            importProcess.steps = @[[NSBlockOperation blockOperationWithBlock:^{
//                importProcess.failed = YES;
//            }]];
//
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            NSURL *downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            download.bytesReceived = 999999;
//            download.downloadedFile = downloadedFile;
//            download.wasSuccessful = YES;
//            download.httpResponseCode = 200;
//
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            [verify(downloadManager) downloadUrl:report.remoteSource];
//
//            [store downloadManager:downloadManager willFinishDownload:download movingToFile:downloadedFile];
//            [fileManager createFilePath:downloadedFile.path contents:nil];
//            [store downloadManager:downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(store.reports).to.contain(report);
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//            expect(report.sourceFile).to.equal(downloadedFile);
//
//            [store retryImportingReport:report];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusDownloading));
//
//            [verify(downloadManager) downloadUrl:report.remoteSource];
//            expect([fileManager fileExistsAtPath:downloadedFile.path]).to.beFalsy();
//            expect([fileManager isDirectoryAtUrl:report.importDir]).to.beTruthy();
//            expect([fileManager isRegularFileAtUrl:[report.importDir URLByAppendingPathComponent:@"dice.obj"]]).to.beTruthy();
//
//            [blueType enqueueImport];
//
//            [store downloadManager:downloadManager willFinishDownload:download movingToFile:downloadedFile];
//            [fileManager createFilePath:downloadedFile.path contents:nil];
//            [store downloadManager:downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(report.importState).to.equal(ReportImportStatusSuccess);
        });

        it(@"can re-download the same url after a download fails", ^{

            failure(@"todo");

//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            download.bytesReceived = 0;
//            download.downloadedFile = nil;
//            download.wasSuccessful = NO;
//            download.httpResponseCode = 503;
//
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            [store downloadManager:store.downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//            expect(report.title).to.equal(@"Download failed");
//            expect(report.isEnabled).to.beFalsy();
//            expect(store.reports).to.contain(report);
//
//            [store retryImportingReport:report];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusDownloading));
//
//            [verifyCount(downloadManager, times(2)) downloadUrl:url];
//
//            expect(report.importState).to.equal(ReportImportStatusDownloading);
//            expect(report.downloadProgress).to.equal(download.percentComplete);
//
//            NSURL *downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
//            download.bytesReceived = download.bytesExpected;
//            download.httpResponseCode = 200;
//            download.wasSuccessful = YES;
//            download.downloadedFile = downloadedFile;
//
//            [blueType enqueueImport];
//
//            [store downloadManager:downloadManager willFinishDownload:download movingToFile:downloadedFile];
//            [fileManager createFilePath:downloadedFile.path contents:nil];
//            [store downloadManager:downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(report.isEnabled).to.beTruthy();
//            expect(report.sourceFile).to.equal(downloadedFile);
//            expect(report.importState).to.equal(ReportImportStatusSuccess);
        });

        it(@"does not import downloads finished in the background", ^{
            failure(@"do it");
        });

        it(@"creates reports for download notifications with no report", ^{

            failure(@"todo");

//            NotificationRecordingObserver *obs = [[[NotificationRecordingObserver
//                observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil]
//                observe:ReportNotification.reportDownloadProgress on:notifications from:store]
//                observe:ReportNotification.reportDownloadComplete on:notifications from:store];
//            DICEDownload *inProgress = [[DICEDownload alloc] initWithUrl:[NSURL URLWithString:@"http://dice.com/test.blue"]];
//            inProgress.bytesExpected = 9876543;
//            inProgress.bytesReceived = 8765432;
//            DICEDownload *finished = [[DICEDownload alloc] initWithUrl:[NSURL URLWithString:@"http://dice.com/test.red"]];
//            finished.bytesReceived = finished.bytesExpected = 1234567;
//            NSURL *finishedFile = [reportsDir URLByAppendingPathComponent:@"test.red"];
//
//            [store downloadManager:downloadManager didReceiveDataForDownload:inProgress];
//            [store downloadManager:downloadManager willFinishDownload:finished movingToFile:finishedFile];
//
//            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(3));
//
//            expect(obs.received[0].notification.name).to.equal(ReportNotification.reportAdded);
//            expect(obs.received[1].notification.name).to.equal(ReportNotification.reportDownloadProgress);
//            expect(obs.received[2].notification.name).to.equal(ReportNotification.reportAdded);
//
//            Report *inProgressReport = obs.received[0].notification.userInfo[@"report"];
//            Report *finishedReport = obs.received[2].notification.userInfo[@"report"];
//
//            expect(inProgressReport.importState).to.equal(ReportImportStatusDownloading);
//            expect(inProgressReport.remoteSource).to.equal(inProgress.url);
//            expect(finishedReport.importState).to.equal(ReportImportStatusDownloading);
//            expect(finishedReport.sourceFile).to.equal(finishedFile);
//            expect(obs.received[0].notification.userInfo[@"report"]).to.beIdenticalTo(inProgressReport);
//            expect(obs.received[1].notification.userInfo[@"report"]).to.beIdenticalTo(inProgressReport);
//
//            [redType enqueueImport];
//            finished.wasSuccessful = YES;
//            finished.downloadedFile = [reportsDir URLByAppendingPathComponent:@"test.red"];
//            [store downloadManager:downloadManager didFinishDownload:finished];
//
//            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(4));
//
//            expect(obs.received[3].notification.name).to.equal(ReportNotification.reportDownloadComplete);
//            expect(obs.received[3].notification.userInfo[@"report"]).to.beIdenticalTo(finishedReport);
//            expect(finishedReport.importState).to.equal(ReportImportStatusNewLocal);
//
//            assertWithTimeout(1.0, thatEventually(@(finishedReport.isImportFinished)), isTrue());
        });

    });

    describe(@"background task handling", ^{

        it(@"starts and ends background task for importing reports", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"test.red", nil];
//            [redType enqueueImport];
//
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];
//
//            assertWithTimeout(1000.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
//            [verify(app) endBackgroundTask:backgroundTaskId];
        });

        it(@"begins and ends only one background task for multiple concurrent imports", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"test.red", @"test.blue", nil];
//            TestImportProcess *redImport = [[redType enqueueImport] block];
//            TestImportProcess *blueImport = [blueType enqueueImport];
//
//            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];
//
//            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
//
//            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.blue"]];
//
//            assertWithTimeout(1000.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
//
//            [verifyCount(app, never()) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
//            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:0];
//
//            [redImport unblock];
//
//            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isEnabled)), isTrue());
//
//            [verify(app) endBackgroundTask:backgroundTaskId];
        });

        it(@"avoids a race condition and does not end the background task until all pending reports are imported", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"test.red", @"test.blue", nil];
//            TestImportProcess *redImport = [[redType enqueueImport] block];
//            TestImportProcess *blueImport = [blueType enqueueImport];
//
//            __block NSOperation *matchRed = nil;
//            [importQueue setOnAddOperation:^(NSOperation *op) {
//                if ([op isKindOfClass:MatchReportTypeToContentAtPathOperation.class]) {
//                    MatchReportTypeToContentAtPathOperation *match = (MatchReportTypeToContentAtPathOperation *) op;
//                    if ([match.report.sourceFile.lastPathComponent isEqualToString:@"test.red"]) {
//                        matchRed = [match block];
//                    }
//                }
//            }];
//
//            [store loadReports];
//
//            [verifyCount(app, times(1)) beginBackgroundTaskWithName:@"dice.background_import" expirationHandler:anything()];
//
//            assertWithTimeout(1000.0, thatEventually(@(blueImport.report.isEnabled && matchRed != nil)), isTrue());
//
//            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:0];
//
//            [matchRed unblock];
//            [redImport unblock];
//
//            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isEnabled)), isTrue());
//
//            [verifyCount(app, never()) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
//            [verifyCount(app, times(1)) endBackgroundTask:backgroundTaskId];
        });

        it(@"begins and ends only one background task for loading reports", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"test.red", @"test.blue", nil];
//            TestImportProcess *redImport = [[redType enqueueImport] block];
//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//
//            [store loadReports];
//
//            assertWithTimeout(1000.0, thatEventually(@(
//                blueImport.report.importState == ReportImportStatusImporting &&
//                redImport.report.importState == ReportImportStatusImporting)), isTrue());
//
//            [verifyCount(app, times(1)) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
//            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:0];
//
//            [redImport unblock];
//
//            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isEnabled)), isTrue());
//
//            [verifyCount(app, never()) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
//            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:backgroundTaskId];
//
//            [blueImport unblock];
//
//            assertWithTimeout(1000.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
//            
//            [verifyCount(app, never()) beginBackgroundTaskWithName:anything() expirationHandler:anything()];
//            [verify(app) endBackgroundTask:backgroundTaskId];
        });

        it(@"saves the import state and stops the background task when the OS calls the expiration handler", ^{

            // TODO: verify the archive extract points get saved when that's implemented

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"test.red", nil];
//            TestImportProcess *redImport = [redType enqueueImport];
//            NSOperation *step = [[NSBlockOperation blockOperationWithBlock:^{}] block];
//            redImport.steps = @[step];
//            HCArgumentCaptor *expirationBlockCaptor = [[HCArgumentCaptor alloc] init];
//
//            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];
//
//            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:(id)expirationBlockCaptor];
//
//            assertWithTimeout(1000.0, thatEventually(@(redImport.steps.firstObject.isExecuting)), isTrue());
//
//            void (^expirationBlock)() = expirationBlockCaptor.value;
//            expirationBlock();
//
//            [verify(app) endBackgroundTask:backgroundTaskId];
//
//            [redImport.steps.firstObject unblock];
//
//            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isImportFinished)), isTrue());
        });

        it(@"ends the background task when the last import fails", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"test.red", @"test.blue", nil];
//            TestImportProcess *redImport = [redType enqueueImport];
//            TestImportProcess *blueImport = [blueType enqueueImport];
//            blueImport.steps = @[[[NSBlockOperation blockOperationWithBlock:^{}] block]];
//
//            [store loadReports];
//
//            assertWithTimeout(1000.0, thatEventually(blueImport.report), notNilValue());
//            assertWithTimeout(1000.0, thatEventually(redImport.report), notNilValue());
//            assertWithTimeout(1000.0, thatEventually(@(redImport.report.isImportFinished)), isTrue());
//
//            [blueImport cancel];
//            [blueImport.steps.firstObject unblock];
//
//            assertWithTimeout(1000.0, thatEventually(@(blueImport.report.isImportFinished)), isTrue());
//
//            [verify(app) endBackgroundTask:backgroundTaskId];
        });

    });

    describe(@"ignoring reserved files in reports dir", ^{

        it(@"can add exclusions", ^{

            failure(@"todo");

//            [blueType enqueueImport];
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"not-excluded.blue"]];
//
//            expect(report).toNot.beNil();
//            expect(store.reports).to.contain(report);
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            [store addReportsDirExclusion:[NSPredicate predicateWithFormat:@"self.lastPathComponent like %@", @"excluded.blue"]];
//
//            [blueType enqueueImport];
//            report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"excluded.blue"]];
//
//            expect(report).to.beNil();
//            expect(store.reports).to.haveCountOf(1);
        });

    });

    describe(@"deleting reports", ^{

        __block NSURL *trashDir;
        __block Report *singleResourceReport;
        __block Report *baseDirReport;

        beforeEach(^{

            failure(@"todo");

//            trashDir = [reportsDir URLByAppendingPathComponent:@"dice.trash" isDirectory:YES];
//            [fileManager setWorkingDirChildren:
//                @"stand-alone.red",
//                @"blue_content/index.blue",
//                @"blue_content/icon.png",
//                nil];
//            ImportProcess *redImport = [redType enqueueImport];
//            ImportProcess *blueImport = [blueType enqueueImport];
//            NSArray<Report *> *reports = [store loadReports];
//
//            assertWithTimeout(1.0, thatEventually(reports), everyItem(hasProperty(@"isImportFinished", isTrue())));
//
//            singleResourceReport = redImport.report;
//            baseDirReport = blueImport.report;
        });

        it(@"performs delete operations at a lower priority and quality of service", ^{

            failure(@"todo");

//            __block MoveFileOperation *moveToTrash;
//            __block DeleteFileOperation *deleteFromTrash;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if ([op isKindOfClass:[MoveFileOperation class]]) {
//                    moveToTrash = (MoveFileOperation *)op;
//                }
//                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
//                    deleteFromTrash = (DeleteFileOperation *)op;
//                }
//            };
//
//            [store deleteReport:singleResourceReport];
//
//            assertWithTimeout(1.0, thatEventually(@(moveToTrash != nil && deleteFromTrash != nil)), isTrue());
//
//            expect(moveToTrash.queuePriority).to.equal(NSOperationQueuePriorityHigh);
//            expect(moveToTrash.qualityOfService).to.equal(NSQualityOfServiceUserInitiated);
//            expect(deleteFromTrash.queuePriority).to.equal(NSOperationQueuePriorityLow);
//            expect(deleteFromTrash.qualityOfService).to.equal(NSQualityOfServiceBackground);
//
//            assertWithTimeout(1.0, thatEventually(@(singleResourceReport.importState)), equalToUnsignedInteger(ReportImportStatusDeleted));
        });

        it(@"immediately disables the report, sets its summary, status, and sends change notification", ^{

            failure(@"todo");

//            expect(store.reports).to.contain(singleResourceReport);
//            expect(singleResourceReport.isEnabled).to.beTruthy();
//
//            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportChanged on:notifications from:store withBlock:nil];
//            importQueue.suspended = YES;
//
//            [store deleteReport:singleResourceReport];
//
//            expect(singleResourceReport.isEnabled).to.equal(NO);
//            expect(singleResourceReport.importState).to.equal(ReportImportStatusDeleting);
//            expect(singleResourceReport.statusMessage).to.equal(@"Deleting content...");
//            expect(observer.received).to.haveCountOf(1);
//            expect(observer.received.firstObject.notification.userInfo[@"report"]).to.beIdenticalTo(singleResourceReport);
//
//            importQueue.suspended = NO;
//
//            assertWithTimeout(1.0, thatEventually(store.reports), isNot(hasItem(singleResourceReport)));
        });

        it(@"removes the report from the list and status is deleted after moving to the trash dir", ^{

            failure(@"todo");

//            __block MoveFileOperation *moveOp;
//            __block DeleteFileOperation *deleteOp;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if ([op isKindOfClass:[MoveFileOperation class]]) {
//                    MoveFileOperation *mv = (MoveFileOperation *)op;
//                    if ([mv.sourceUrl isEqual:singleResourceReport.importDir]) {
//                        moveOp = (MoveFileOperation *)[op block];
//                    }
//                }
//                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
//                    deleteOp = (DeleteFileOperation *)[op block];
//                }
//            };
//
//            [store deleteReport:singleResourceReport];
//
//            assertWithTimeout(1.0, thatEventually(moveOp), isNot(nilValue()));
//
//            expect(singleResourceReport.importState).to.equal(ReportImportStatusDeleting);
//
//            [moveOp unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(moveOp.isFinished)), isTrue());
//            assertWithTimeout(1.0, thatEventually(store.reports), isNot(hasItem(singleResourceReport)));
//
//            expect(singleResourceReport.importState).to.equal(ReportImportStatusDeleted);
//
//            [deleteOp unblock];
        });

        it(@"sets the report status when finished deleting", ^{

            failure(@"todo");
            
//            [store deleteReport:singleResourceReport];
//
//            assertWithTimeout(1.0, thatEventually(@(singleResourceReport.importState)), equalToUnsignedInteger(ReportImportStatusDeleted));
        });

        it(@"creates the trash dir if it does not exist", ^{

            __block BOOL isDir = YES;
            expect([fileManager fileExistsAtPath:trashDir.path isDirectory:(BOOL *)&isDir]).to.equal(NO);
            expect(isDir).to.beFalsy();

            __block BOOL createdOnBackgroundThread = NO;
            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *dir, BOOL createIntermediates, NSError *__autoreleasing *err) {
                if ([dir hasPrefix:trashDir.path]) {
                    createdOnBackgroundThread = !NSThread.isMainThread;
                }
                return YES;
            };

            __block DeleteFileOperation *deleteOp;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteOp = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:trashDir.path isDirectory:(BOOL * _Nullable)&isDir] && isDir)), isTrue());

            expect(createdOnBackgroundThread).to.beTruthy();

            assertWithTimeout(1.0, thatEventually(@(deleteOp.isFinished)), isTrue());
        });

        it(@"does not load a report for the trash dir", ^{

            failure(@"todo");

//            [fileManager createDirectoryAtURL:trashDir withIntermediateDirectories:YES attributes:nil error:NULL];
//
//            NSArray *reports = [store loadReports];
//
//            expect(reports).to.haveCountOf(2);
//
//            assertWithTimeout(1.0, thatEventually(reports), everyItem(hasProperty(@"isImportFinished", isTrue())));
        });

        it(@"moves the import dir to a unique trash dir", ^{

            __block MoveFileOperation *moveToTrash;
            __block DeleteFileOperation *deleteFromTrash;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    moveToTrash = (MoveFileOperation *)op;
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteFromTrash = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:baseDirReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:baseDirReport.baseDir.path])), isFalse());

            expect(moveToTrash).toNot.beNil();
            expect(moveToTrash.sourceUrl).to.equal(baseDirReport.importDir);
            expect(moveToTrash.destUrl.path).to.beginWith(trashDir.path);

            NSString *reportParentInTrash = [moveToTrash.destUrl.path pathRelativeToPath:trashDir.path];
            reportParentInTrash = reportParentInTrash.pathComponents.firstObject;
            NSUUID *uniqueTrashDirName = [[NSUUID alloc] initWithUUIDString:reportParentInTrash];

            expect(moveToTrash.destUrl.path).to.endWith(baseDirReport.importDir.lastPathComponent);
            expect(uniqueTrashDirName).toNot.beNil();

            assertWithTimeout(1.0, thatEventually(@(deleteFromTrash.isFinished)), isTrue());

            expect(deleteFromTrash.fileUrl).to.equal([trashDir URLByAppendingPathComponent:reportParentInTrash isDirectory:YES]);
        });

        it(@"moves the source file to a unique trash dir if it exists", ^{

            [fileManager createFilePath:singleResourceReport.sourceFile.path contents:[NSData data]];

            __block MoveFileOperation *moveSourceFileToTrash;
            __block MoveFileOperation *moveImportDirToTrash;
            __block DeleteFileOperation *deleteFromTrash;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[MoveFileOperation class]]) {
                    MoveFileOperation *moveToTrash = (MoveFileOperation *)op;
                    if ([moveToTrash.sourceUrl isEqual:singleResourceReport.sourceFile]) {
                        moveSourceFileToTrash = moveToTrash;
                    }
                    else if ([moveToTrash.sourceUrl isEqual:singleResourceReport.importDir]) {
                        moveImportDirToTrash = moveToTrash;
                    }
                }
                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
                    deleteFromTrash = (DeleteFileOperation *)op;
                }
            };

            [store deleteReport:singleResourceReport];

            assertWithTimeout(1.0, thatEventually(@([fileManager fileExistsAtPath:singleResourceReport.rootFile.path])), isFalse());

            expect(moveSourceFileToTrash).toNot.beNil();
            expect(moveSourceFileToTrash.destUrl.path).to.beginWith(trashDir.path);
            expect(moveSourceFileToTrash.destUrl.path).to.endWith(singleResourceReport.sourceFile.lastPathComponent);

            expect(moveImportDirToTrash).toNot.beNil();
            expect(moveImportDirToTrash.destUrl.path).to.beginWith(trashDir.path);
            expect(moveImportDirToTrash.destUrl.path).to.endWith(singleResourceReport.importDir.lastPathComponent);

            expect(deleteFromTrash).toNot.beNil();
            NSString *reportParentInTrash = [deleteFromTrash.fileUrl.path pathRelativeToPath:trashDir.path];
            reportParentInTrash = reportParentInTrash.pathComponents.firstObject;
            NSUUID *uniqueTrashDirName = [[NSUUID alloc] initWithUUIDString:reportParentInTrash];

            expect(uniqueTrashDirName).toNot.beNil();
            expect(moveSourceFileToTrash.destUrl.path.stringByDeletingLastPathComponent.lastPathComponent).to.equal(reportParentInTrash);
            expect(moveImportDirToTrash.destUrl.path.stringByDeletingLastPathComponent.lastPathComponent).to.equal(reportParentInTrash);

            assertWithTimeout(1.0, thatEventually(@(deleteFromTrash.isFinished)), isTrue());

            expect(deleteFromTrash.fileUrl).to.equal([trashDir URLByAppendingPathComponent:reportParentInTrash isDirectory:YES]);
        });

        it(@"cannot delete a report while importing", ^{

            failure(@"todo");

//            NSURL *importingReportUrl = [reportsDir URLByAppendingPathComponent:@"importing.red"];
//            [fileManager createFileAtPath:importingReportUrl.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
//            TestImportProcess *process = [[redType enqueueImport] block];
//
//            Report *importingReport = [store attemptToImportReportFromResource:importingReportUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(importingReport.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            expect(importingReport.importState).to.equal(ReportImportStatusImporting);
//
//            [store deleteReport:importingReport];
//
//            expect(importingReport.importState).to.equal(ReportImportStatusImporting);
//
//            [process unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(importingReport.isImportFinished)), isTrue());
        });

        it(@"sends a notification when a report is removed from the reports list", ^{

            failure(@"todo");

//            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportRemoved on:store.notifications from:store withBlock:^(NSNotification *notification) {
//                expect(store.reports).notTo.contain(singleResourceReport);
//            }];
//            [store deleteReport:singleResourceReport];
//
//            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(1));
//
//            ReceivedNotification *removed = observer.received.firstObject;
//
//            expect(removed.notification.userInfo[@"report"]).to.beIdenticalTo(singleResourceReport);
        });

        it(@"can delete a failed download report", ^{

            failure(@"todo");

//            NSURL *url = [NSURL URLWithString:@"http://dice.com/fail"];
//            Report *failed = [store attemptToImportReportFromResource:url];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.wasSuccessful = NO;
//            [store downloadManager:downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(failed.isImportFinished)), isTrue());
//
//            expect(failed.importState).to.equal(ReportImportStatusFailed);
//            expect(store.reports).to.contain(failed);
//
//            [store deleteReport:failed];
//
//            assertWithTimeout(1.0, thatEventually(@(failed.importState)), equalToUnsignedInteger(ReportImportStatusDeleted));
//
//            expect(store.reports).notTo.contain(failed);
        });

        it(@"can delete a failed import report", ^{

            failure(@"todo");

//            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"failed.blue"];
//            [fileManager createFilePath:sourceFile.path contents:nil];
//            TestImportProcess *defeatist = [blueType enqueueImport];
//            [defeatist.steps.firstObject cancel];
//
//            Report *doomed = [store attemptToImportReportFromResource:sourceFile];
//
//            assertWithTimeout(1.0, thatEventually(@(doomed.isImportFinished)), isTrue());
//
//            expect(doomed.importState).to.equal(ReportImportStatusFailed);
//            expect(doomed.importDir).toNot.beNil();
//            expect(store.reports).to.contain(doomed);
//            expect([fileManager isDirectoryAtUrl:doomed.importDir]).to.beTruthy();
//
//            [store deleteReport:doomed];
//
//            assertWithTimeout(1.0, thatEventually(@(doomed.importState)), equalToUnsignedInteger(ReportImportStatusDeleted));
//
//            expect(store.reports).notTo.contain(doomed);
//            expect([fileManager isDirectoryAtUrl:doomed.importDir]).to.beFalsy();
//            expect([fileManager isRegularFileAtUrl:sourceFile]).to.beFalsy();
        });

    });

    xdescribe(@"core data concurrency", ^{

        it(@"blocks the main thread when firing a fault on the main thread context and a block is waiting to run on the parent private context", ^{

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.remoteSource = [NSURL URLWithString:@"http://dice.com/concurrency"];
            [verifyDb MR_saveToPersistentStoreAndWait];

            expect(report.isFault).to.beTruthy();

            NSCondition *blocked = [[NSCondition alloc] init];
            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"concurrency.zip"];
            [reportDb performBlock:^{
                [blocked lock];
                [blocked waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
                [blocked unlock];
                Report *bgReport = [reportDb executeFetchRequest:[Report fetchRequest] error:NULL].firstObject;
                bgReport.sourceFile = sourceFile;
            }];

            NSTimeInterval start = NSDate.timeIntervalSinceReferenceDate;
            NSURL *mainSourceFile = report.sourceFile;
            NSTimeInterval finish = NSDate.timeIntervalSinceReferenceDate;

            expect(mainSourceFile).to.equal(sourceFile);
            expect(finish).toNot.beCloseToWithin(start, 0.8);
        });

        it(@"does not block the main thread when accessing a property on a non-fault entity while a block is running on a parent private context", ^{

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.remoteSource = [NSURL URLWithString:@"http://dice.com/concurrency"];
            [verifyDb MR_saveToPersistentStoreAndWait];

            // comment the following line to see that having a fault entity will deadlock the test
            // because accessing sourceFile on the main thread will cause the main thread to block
            // on a mutext wait while the background block is running; hence the main thread will
            // never get to unlocking with the MAIN_ACCESSED_ENTITY condition, which means background
            // block will never acquire the lock with that condiition, deadlocking the threads.
            [report willAccessValueForKey:nil];
            expect(report.isFault).to.beFalsy();

            NSInteger MAIN_WAITING = 0, BG_BLOCK_RUNNING = 1, BG_BLOCK_FINISHED = 2, MAIN_ACCESSED_ENTITY = 3;
            NSConditionLock *canProceed = [[NSConditionLock alloc] initWithCondition:MAIN_WAITING];

            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"concurrency.zip"];
            [reportDb performBlock:^{
                [canProceed lockWhenCondition:MAIN_WAITING];
                [canProceed unlockWithCondition:BG_BLOCK_RUNNING];
                [canProceed lockWhenCondition:MAIN_ACCESSED_ENTITY];

                Report *bgReport = [reportDb executeFetchRequest:[Report fetchRequest] error:NULL].firstObject;
                bgReport.sourceFile = sourceFile;

                [canProceed unlockWithCondition:BG_BLOCK_FINISHED];
            }];

            [canProceed lockWhenCondition:BG_BLOCK_RUNNING];

            NSURL *mainSourceFile = report.sourceFile;
            expect(mainSourceFile).to.beNil();

            [canProceed unlockWithCondition:MAIN_ACCESSED_ENTITY];
            [canProceed lockWhenCondition:BG_BLOCK_FINISHED];
            [canProceed unlock];
        });
    });

    describe(@"notifications", ^{

        it(@"works as expected", ^{

            NSMutableArray<NSNotification *> *notes = [NSMutableArray array];
            NSNotificationCenter *notifications = [[NSNotificationCenter alloc] init];
            [notifications addObserverForName:@"test.notification" object:self queue:nil usingBlock:^(NSNotification * _Nonnull note) {
                [notes addObject:note];
            }];
            NotificationRecordingObserver *recorder = [NotificationRecordingObserver observe:@"test.notification" on:notifications from:self withBlock:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [notifications postNotificationName:@"test.notification" object:self];
            });
            
            assertWithTimeout(1.0, thatEventually(@(notes.count)), equalToUnsignedInteger(1));

            assertWithTimeout(1.0, thatEventually(@(recorder.received.count)), equalToUnsignedInteger(1));
        });

    });

});

SpecEnd
