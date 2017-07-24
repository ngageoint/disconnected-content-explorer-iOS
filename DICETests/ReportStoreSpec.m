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
    [self performBlockAndWait:^{}];
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
        waitUntilTimeout(1.0, ^(DoneCallback done) {
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

            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);
        });

        it(@"starts in new state to enter downloading when source url starts with http", ^{

            [verifyResults performFetch:NULL];
            NSURL *source = [NSURL URLWithString:@"https://dice.com/test.zip"];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.lastObject;

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

        it(@"has a uti when inspecting source file completes", ^{

            [verifyResults performFetch:NULL];
            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red" isDirectory:NO];
            [fileManager setWorkingDirChildren:@"report.red", nil];

            Report *report = [Report MR_createEntityInContext:verifyDb];
            report.importState = ReportImportStatusNew;
            report.importStateToEnter = ReportImportStatusInspectingSourceFile;
            report.sourceFile = source;
            [verifyDb MR_saveToPersistentStoreAndWait];
            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusInspectingSourceFile));

            expect(report.uti).to.equal(UTI_RED);
        });
    });

    fdescribe(@"importing stand-alone files from the documents directory", ^{

        beforeEach(^{
        });

        it(@"transitions from inspecting source file to inspecting content", ^{

            NSURL *source = [reportsDir URLByAppendingPathComponent:@"report.red" isDirectory:NO];
            verifyResults.fetchRequest.predicate = [Report predicateForSourceUrl:source];
            [verifyResults performFetch:NULL];
            [store attemptToImportReportFromResource:source];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;

            expect(report.importState).to.equal(ReportImportStatusNew);
            expect(report.importStateToEnter).to.equal(ReportImportStatusInspectingSourceFile);

            [store advancePendingImports];

            assertWithTimeout(1.0, thatEventually(@(report.importStateToEnter)), equalToUnsignedInteger(ReportImportStatusInspectingContent));
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
            report.sourceFile = source;
            report.importDir = [reportsDir URLByAppendingPathComponent:@"report.red.dice_import" isDirectory:YES];
            report.importState = ReportImportStatusInspectingContent;
            report.importStateToEnter = ReportImportStatusMovingContent;
            report.uti = UTI_RED;
            report.reportTypeId = redType.reportTypeId;

            [verifyDb MR_saveToPersistentStoreAndWait];

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
            expect([fileManager isDirectoryAtUrl:report.baseDir]).to.beTruthy();
            expect([fileManager isRegularFileAtUrl:report.rootFile]).to.beTruthy();
            expect(movedSourceFileTo).to.equal(report.rootFile.path);
            expect(movedOnImportQueue).to.beTruthy();
        });

        it(@"imports a report with the capable report type", ^{

            NSURL *sourceUrl = [reportsDir URLByAppendingPathComponent:@"report.red"];
            id<NSFetchedResultsControllerDelegate> verify = mockProtocol(@protocol(NSFetchedResultsControllerDelegate));
            verifyResults.delegate = verify;
            verifyResults.fetchRequest.predicate = [sourceUrlIsFinished predicateWithSubstitutionVariables:@{@"url": sourceUrl}];
            [givenVoid([verify controllerDidChangeContent:verifyResults]) willDo:^id _Nonnull(NSInvocation * _Nonnull invoc) {
                return nil;
            }];
            [verifyResults performFetch:NULL];

            [fileManager setWorkingDirChildren:@"report.red", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.isFinished)), isTrue());

            [reportDb performBlockAndWait:^{
                Report *report = redImport.report;
                expect(report).toNot.beNil();
                expect(report.isEnabled).to.beTruthy();
            }];

            assertWithTimeout(1.0, thatEventually(verifyResults.fetchedObjects), hasCountOf(1));

            Report *report = verifyResults.fetchedObjects.firstObject;
            expect(report).toNot.beNil();
            expect(report.isEnabled).to.beTruthy();
        });

        it(@"moves source file to base dir in import dir before importing", ^{

            failure(@"todo");

//            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"report.red"];
//            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"report.red.dice_import" isDirectory:YES];
//            NSURL *baseDir = [importDir URLByAppendingPathComponent:@"dice_content" isDirectory:YES];
//            NSURL *rootFile = [baseDir URLByAppendingPathComponent:sourceFile.lastPathComponent];
//
//            __block atomic_bool assignedToReportBeforeCreated; atomic_init(&assignedToReportBeforeCreated, NO);
//            __block atomic_bool createdImportDirOnMainThread; atomic_init(&createdImportDirOnMainThread, NO);
//            __block atomic_bool sourceFileMoved; atomic_init(&sourceFileMoved, NO);
//            __block atomic_bool movedOnBackgroundThread; atomic_init(&movedOnBackgroundThread, NO);
//            __block atomic_bool movedBeforeImport; atomic_init(&movedBeforeImport, NO);
//
//            __block Report *report;
//
//            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *path, BOOL createIntermediates, NSError **err) {
//                if ([path isEqualToString:importDir.path]) {
//                    atomic_store((atomic_bool *)&createdImportDirOnMainThread, NSThread.isMainThread);
//                }
//                else if ([path isEqualToString:baseDir.path]) {
//                    BOOL val = [report.baseDir.path isEqualToString:path] && [report.rootFile isEqual:rootFile] && createIntermediates;
//                    atomic_store((atomic_bool *)&assignedToReportBeforeCreated, val);
//                }
//                return YES;
//            };
//            fileManager.onMoveItemAtPath = ^BOOL(NSString *sourcePath, NSString *destPath, NSError *__autoreleasing *error) {
//                if ([sourcePath isEqualToString:sourceFile.path] && [destPath isEqualToString:rootFile.path]) {
//                    atomic_store((atomic_bool *)&sourceFileMoved, [report.rootFile isEqual:rootFile]);
//                    atomic_store((atomic_bool *)&movedOnBackgroundThread, !NSThread.isMainThread);
//                }
//                return YES;
//            };
//            TestImportProcess *importProcess = [[redType enqueueImport] block];
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if (op == importProcess.steps.firstObject) {
//                    atomic_store((atomic_bool *)&movedBeforeImport, (_Bool)sourceFileMoved);
//                }
//            };
//
//            [fileManager setWorkingDirChildren:sourceFile.lastPathComponent, nil];
//            report = [store attemptToImportReportFromResource:sourceFile];
//
//            expect(report.sourceFile).to.equal(sourceFile);
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            expect(atomic_load((atomic_bool *)&sourceFileMoved)).to.beTruthy();
//
//            [importProcess unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(report.sourceFile).to.equal(sourceFile);
//            expect(report.importDir).to.equal(importDir);
//            expect(report.baseDir).to.equal(baseDir);
//            expect(report.rootFile).to.equal(rootFile);
//            expect(atomic_load((atomic_bool *)&assignedToReportBeforeCreated)).to.beTruthy();
//            expect(atomic_load((atomic_bool *)&movedBeforeImport)).to.beTruthy();
//            expect(atomic_load((atomic_bool *)&movedOnBackgroundThread)).to.beTruthy();
        });

        it(@"posts a notification when the import begins", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"report.red", nil];
//            NotificationRecordingObserver *observer = [NotificationRecordingObserver
//                observe:ReportNotification.reportImportBegan on:store.notifications from:store withBlock:nil];
//            [redType enqueueImport];
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(observer.received.count).to.equal(1);
//
//            ReceivedNotification *received = observer.received.lastObject;
//            NSNotification *note = received.notification;
//
//            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.importState).to.equal(ReportImportStatusSuccess);
//            expect(received.wasMainThread).to.equal(YES);
        });

        it(@"posts a notification when the import finishes successfully", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"report.red", nil];
//            NotificationRecordingObserver *observer = [NotificationRecordingObserver
//                observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
//            [redType enqueueImport];
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            ReceivedNotification *received = observer.received.lastObject;
//            NSNotification *note = received.notification;
//
//            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.importState).to.equal(ReportImportStatusSuccess);
//            expect(received.wasMainThread).to.equal(YES);
        });

        it(@"posts a notification when the import finishes unsuccessfully", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"report.red", nil];
//            NotificationRecordingObserver *observer = [NotificationRecordingObserver
//                observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
//            TestImportProcess *redImport = [redType enqueueImport];
//            [redImport.steps.firstObject cancel];
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            ReceivedNotification *received = observer.received.lastObject;
//            NSNotification *note = received.notification;
//
//            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//            expect(received.wasMainThread).to.equal(YES);
        });

        it(@"returns a report even if the url cannot be imported", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"report.green", nil];
//            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            expect(report).notTo.beNil();
//            expect(report.sourceFile).to.equal(url);
//            expect(store.reports).to.contain(report);
        });

        it(@"assigns an error message if the report type was unknown", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"report.green", nil];
//            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusFailed));
//
//            expect(report.summary).to.equal(@"Unknown content type");
        });

        it(@"immediately adds the report to the report list", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"report.red", nil];
//            TestImportProcess *import = [[redType enqueueImport] block];
//            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.red"];
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            expect(store.reports).to.contain(report);
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            expect(report.title).to.equal(report.sourceFile.lastPathComponent);
//            expect(report.summary).to.equal(@"Importing content...");
//            expect(report.isEnabled).to.equal(NO);
//            
//            [import unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(store.reports).to.contain(report);
        });

        it(@"sends a notification serially about adding the report", ^{

            failure(@"todo");

//            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil];
//
//            TestImportProcess *importProcess = [[redType enqueueImport] block];
//
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];
//
//            expect(observer.received.count).to.equal(1);
//
//            ReceivedNotification *received = observer.received.firstObject;
//            Report *receivedReport = received.notification.userInfo[@"report"];
//            expect(received.notification.name).to.equal(ReportNotification.reportAdded);
//            expect(receivedReport).to.beIdenticalTo(report);
//
//            [importProcess unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            [notifications removeObserver:observer];
        });

        it(@"does not start an import for a report file already importing", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"report1.red", nil];
//            TestImportProcess *import = [[redType enqueueImport] block];
//            NotificationRecordingObserver *observer = [NotificationRecordingObserver
//                observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil];
//            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];
//            Report *report = [store attemptToImportReportFromResource:reportUrl];
//            Report *reportAgain = [store attemptToImportReportFromResource:reportUrl];
//
//            expect(store.reports).to.haveCountOf(1);
//            expect(reportAgain).to.beIdenticalTo(report);
//            expect(observer.received).to.haveCountOf(1);
//            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
//            expect(notificationReport).to.beIdenticalTo(report);
//            expect(store.reports).to.haveCountOf(1);
//            expect(store.reports.firstObject).to.beIdenticalTo(notificationReport);
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            notificationReport = nil;
//            [observer.received removeAllObjects];
//
//            Report *sameReport = [store attemptToImportReportFromResource:reportUrl];
//
//            [import unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            expect(sameReport).to.beIdenticalTo(report);
//            expect(store.reports).to.haveCountOf(1);
//            expect(observer.received).to.haveCountOf(0);
//
//            [notifications removeObserver:observer];
        });

        it(@"posts a failure notification if no report type matches the content", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"oops.der", nil];
//            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"oops.der"]];
//
//            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(1));
//
//            NSNotification *note = obs.received.firstObject.notification;
//
//            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.importState).to.equal(ReportImportStatusFailed);
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

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"ignore.dice_import/blue_content/index.blue", nil];
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"ignore.dice_import" isDirectory:YES]];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//            expect(report.sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"ignore.dice_import" isDirectory:YES]);
//            expect(report.importDir).to.beNil();
//            expect(report.baseDir).to.beNil();
//            expect(report.rootFile).to.beNil();
//            expect(report.isEnabled).to.beFalsy();
        });

        it(@"moves the directory to an import dir", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue_base/index.blue", nil];
//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//
//            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]];
//
//            assertWithTimeout(1.0, thatEventually(report.baseDir), notNilValue());
//
//            expect(report.importDir).to.equal([reportsDir URLByAppendingPathComponent:@"blue_base.dice_import" isDirectory:YES]);
//            expect(report.baseDir).to.equal([report.importDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]);
//            expect(report.rootFile).to.beNil();
//
//            [blueImport unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"blue_base.dice_import" isDirectory:YES];
//            NSURL *baseDir = [importDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
//            NSURL *rootFile = [baseDir URLByAppendingPathComponent:@"index.blue"];
//
//            expect(report.sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES]);
//            expect(report.importDir).to.equal(importDir);
//            expect(report.baseDir).to.equal(baseDir);
//            expect(report.rootFile).to.equal(rootFile);
        });

        it(@"parses the report descriptor if present in base dir as metadata.json", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", nil];
//            [fileManager createFilePath:@"blue_base/metadata.json" contents:
//                [@"{\"title\": \"Title From Descriptor\", \"description\": \"Summary from descriptor\"}"
//                    dataUsingEncoding:NSUTF8StringEncoding]];
//            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
//            [blueType enqueueImport];
//            Report *report = [store attemptToImportReportFromResource:baseDir];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            expect(report.title).to.equal(@"Title From Descriptor");
//            expect(report.summary).to.equal(@"Summary from descriptor");
        });

        it(@"parses the report descriptor if present in base dir as dice.json", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", nil];
//            [fileManager createFilePath:@"blue_base/dice.json" contents:
//                [@"{\"title\": \"Title From Descriptor\", \"description\": \"Summary from descriptor\"}"
//                    dataUsingEncoding:NSUTF8StringEncoding]];
//            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
//            [blueType enqueueImport];
//            Report *report = [store attemptToImportReportFromResource:baseDir];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            expect(report.title).to.equal(@"Title From Descriptor");
//            expect(report.summary).to.equal(@"Summary from descriptor");
        });

        it(@"prefers dice.json to metadata.json", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue_base/", @"blue_base/index.blue", @"blue_base/metadata.json", @"blue_base/dice.json", nil];
//            [fileManager createFilePath:@"blue_base/dice.json" contents:
//                [@"{\"title\": \"Title From dice.json\", \"description\": \"Summary from dice.json\"}"
//                    dataUsingEncoding:NSUTF8StringEncoding]];
//            [fileManager createFilePath:@"blue_base/metadata.json" contents:
//                [@"{\"title\": \"Title From metadata.json\", \"description\": \"Summary from metadata.json\"}"
//                    dataUsingEncoding:NSUTF8StringEncoding]];
//            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
//            [blueType enqueueImport];
//            Report *report = [store attemptToImportReportFromResource:baseDir];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            expect(report.title).to.equal(@"Title From dice.json");
//            expect(report.summary).to.equal(@"Summary from dice.json");
        });

        it(@"sets a nil summary if the report descriptor is unavailable", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue_base/", @"blue_base/index.blue", nil];
//            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
//            [blueType enqueueImport];
//            Report *report = [store attemptToImportReportFromResource:baseDir];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            expect(report.summary).to.beNil();
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

        it(@"creates an import dir for the archive", ^{

            failure(@"todo");

//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
//                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//
//            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
//            __block Report *report;
//            __block BOOL createdImportDir = NO;
//            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *path, BOOL createIntermediates, NSError *__autoreleasing *error) {
//                if ([path isEqualToString:importDir.path]) {
//                    createdImportDir = [report.importDir isEqual:importDir] && NSThread.isMainThread;
//                }
//                return YES;
//            };
//
//            report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusExtracting));
//
//            expect(report.sourceFile).to.equal(archiveUrl);
//            expect(report.importDir).to.equal(importDir);
//            expect(createdImportDir).to.beTruthy();
//
//            [blueImport unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
        });

        it(@"creates a base dir if the archive has no base dir", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
//            NSURL *baseDir = [importDir URLByAppendingPathComponent:@"dice_content" isDirectory:YES];
//            __block BOOL createdBaseDir = NO;
//            __block Report *report;
//            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *path, BOOL intermediates, NSError **error) {
//                createdBaseDir = [path isEqualToString:baseDir.path];
//                return YES;
//            };
//
//            NSFileHandle *handle = mock([NSFileHandle class]);
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return handle;
//                };
//            }];
//
//            report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusExtracting));
//
//            expect(createdBaseDir).to.beTruthy();
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            expect(report.baseDir).to.equal(baseDir);
//
//            [blueImport unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not create a new base dir if archive has base dir", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
//                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//            NSURL *importDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dice_import" isDirectory:YES];
//            NSURL *baseDir = [importDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];
//            __block BOOL createdArchiveBaseDir = NO;
//            __block BOOL createdUnexpectedDir = NO;
//            __block Report *report;
//
//            fileManager.onCreateDirectoryAtPath = ^BOOL(NSString *path, BOOL intermediates, NSError **error) {
//                if ([path isEqualToString:baseDir.path]) {
//                    // the archive extraction implicitly creates base dir on background thread
//                    createdArchiveBaseDir = [report.baseDir isEqual:baseDir] && report.importState == ReportImportStatusExtracting && !NSThread.isMainThread;
//                }
//                else {
//                    createdUnexpectedDir = ![path isEqualToString:importDir.path];
//                }
//                return YES;
//            };
//
//            NSFileHandle *handle = mock([NSFileHandle class]);
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return handle;
//                };
//            }];
//
//            report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusExtracting));
//
//            expect(report.baseDir).to.equal(baseDir);
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            expect(createdArchiveBaseDir).to.beTruthy();
//
//            [blueImport unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            expect(createdUnexpectedDir).to.beFalsy();
//
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"deletes the archive file after extracting the contents", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//
//            NSFileHandle *handle = mock([NSFileHandle class]);
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return handle;
//                };
//            }];
//
//            __block DeleteFileOperation *deleteArchive;
//            __block BOOL queuedOnMainThread = NO;
//            __block BOOL multipleDeletes = NO;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if ([op isKindOfClass:[DeleteFileOperation class]]) {
//                    DeleteFileOperation *del = (DeleteFileOperation *)op;
//                    if ([del.fileUrl isEqual:archiveUrl]) {
//                        if (deleteArchive) {
//                            multipleDeletes = YES;
//                            return;
//                        }
//                        queuedOnMainThread = NSThread.isMainThread;
//                        deleteArchive = [del block];
//                    }
//                }
//            };
//
//            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.beTruthy();
//
//            Report *report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            expect(deleteArchive).toNot.beNil();
//            expect(queuedOnMainThread).to.beTruthy();
//            expect(multipleDeletes).to.beFalsy();
//
//            [deleteArchive unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(deleteArchive.isFinished)), isTrue());
//
//            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.beFalsy();
//            expect(report.importState).to.equal(ReportImportStatusImporting);
//
//            [blueImport unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            [importQueue waitUntilAllOperationsAreFinished];
//
//            expect(multipleDeletes).to.beFalsy();
//            
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not delete the archive file if the extract fails", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return nil;
//                };
//            }];
//
//            __block DICEExtractReportOperation *extract;
//            __block DeleteFileOperation *deleteArchive;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
//                    extract = (DICEExtractReportOperation *)op;
//                    [extract cancel];
//                }
//                else if ([op isKindOfClass:[DeleteFileOperation class]]) {
//                    deleteArchive = (DeleteFileOperation *)op;
//                }
//            };
//
//            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.equal(YES);
//
//            Report *report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            [importQueue waitUntilAllOperationsAreFinished];
//
//            expect(extract).toNot.beNil();
//            expect(extract.wasSuccessful).to.beFalsy();
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.equal(YES);
//            expect(deleteArchive).to.beNil();
//            
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes import status to extracting and posts update notification", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//            TestImportProcess *blueImport = [blueType enqueueImport];
//
//            NSFileHandle *handle = mock([NSFileHandle class]);
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return handle;
//                };
//            }];
//
//            __block DICEExtractReportOperation *extract;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
//                    if (extract != nil) {
//                        failure(@"multiple extract operations queued for the same report archive");
//                        return;
//                    }
//                    extract = (DICEExtractReportOperation *)op;
//                    [extract block];
//                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
//                }
//            };
//
//            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportExtractProgress on:notifications from:store withBlock:nil];
//
//            Report *report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToUnsignedInteger(1));
//
//            ReceivedNotification *received = observer.received.firstObject;
//            NSNotification *note = received.notification;
//
//            expect(received.wasMainThread).to.equal(YES);
//            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.importState).to.equal(ReportImportStatusExtracting);
//
//            [extract unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
//            
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"posts notifications about extract progress", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:(1 << 20)]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//            [blueType enqueueImport];
//            NSFileHandle *handle = mock([NSFileHandle class]);
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return handle;
//                };
//            }];
//            NSMutableArray<NSNotification *> *extractUpdates = [NSMutableArray array];
//            __block NSNotification *finished = nil;
//            [store.notifications addObserverForName:ReportNotification.reportExtractProgress object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
//                [extractUpdates addObject:note];
//            }];
//            [store.notifications addObserverForName:ReportNotification.reportImportFinished object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
//                finished = note;
//            }];
//
//            [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(2.0, thatEventually(finished), notNilValue());
//
//            expect(extractUpdates.count).to.beGreaterThan(10);
//            expect(extractUpdates.lastObject.userInfo[@"percentExtracted"]).to.equal(@100);
//
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"load reports does not create multiple reports while the archive is extracting", ^{

            failure(@"todo");

//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            [fileManager setWorkingDirChildren:archiveUrl.lastPathComponent, nil];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
//                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//
//            NSFileHandle *handle = mock([NSFileHandle class]);
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return handle;
//                };
//            }];
//
//            __block DICEExtractReportOperation *extract;
//            __block BOOL multipleExtracts = NO;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
//                    if (!NSThread.isMainThread) {
//                        [NSException raise:NSInternalInconsistencyException format:@"added extract operation from background thread"];
//                    }
//                    if (extract != nil) {
//                        multipleExtracts = YES;
//                        return;
//                    }
//                    extract = (DICEExtractReportOperation *)op;
//                    [extract block];
//                }
//            };
//
//            NSArray<Report *> *reports1 = [[store loadReports] copy];
//            Report *report = reports1.firstObject;
//
//            expect(reports1.count).to.equal(1);
//            expect(report.sourceFile).to.equal(archiveUrl);
//
//            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());
//
//            NSUInteger opCount = importQueue.operationCount;
//
//            NSArray *reports2 = [[store loadReports] copy];
//
//            expect(reports2.count).to.equal(reports1.count);
//            expect(reports2.firstObject).to.beIdenticalTo(report);
//            expect(importQueue.operationCount).to.equal(opCount);
//
//            [blueType enqueueImport];
//            [extract unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect(multipleExtracts).to.beFalsy();
//
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"single import does not create multiple reports while the archive is extracting", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//
//            NSFileHandle *handle = mock([NSFileHandle class]);
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    return handle;
//                };
//            }];
//
//            __block DICEExtractReportOperation *extract;
//            __block BOOL multipleExtracts = NO;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
//                    if (!NSThread.isMainThread) {
//                        [NSException raise:NSInternalInconsistencyException format:@"added extract operation from background thread"];
//                    }
//                    if (extract != nil) {
//                        multipleExtracts = YES;
//                        return;
//                    }
//                    extract = (DICEExtractReportOperation *)op;
//                    [extract block];
//                }
//            };
//
//            Report *report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());
//
//            NSURL *importDir = report.importDir;
//            NSURL *importDirParent = importDir.URLByDeletingLastPathComponent;
//
//            expect(importDir).toNot.beNil();
//            expect(importDirParent.pathComponents).to.equal(reportsDir.pathComponents);
//
//            NSUInteger opCount = importQueue.operationCount;
//
//            Report *dupFromArchiveUrl = [store attemptToImportReportFromResource:archiveUrl];
//            Report *dupFromImportDir = [store attemptToImportReportFromResource:report.importDir];
//
//            expect(dupFromArchiveUrl).to.beIdenticalTo(report);
//            expect(dupFromImportDir).to.beIdenticalTo(report);
//            expect(store.reports).to.haveCountOf(1);
//            expect(importQueue.operationCount).to.equal(opCount);
//
//            [blueType enqueueImport];
//            [extract unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());
//
//            expect(multipleExtracts).to.beFalsy();
//
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not start an import process if the extraction fails", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    *errOut = [[NSError alloc] initWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"error for test"}];
//                    return nil;
//                };
//            }];
//
//            // intentionally do not enqueue import process to force failure if attempted
//            // TestImportProcess *blueImport = [blueType enqueueImport];
//
//            __block DICEExtractReportOperation *extract;
//            __block BOOL multipleExtracts = NO;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
//                    if (!NSThread.isMainThread) {
//                        [NSException raise:NSInternalInconsistencyException format:@"added extract operation from background thread"];
//                    }
//                    if (extract != nil) {
//                        multipleExtracts = YES;
//                        return;
//                    }
//                    extract = (DICEExtractReportOperation *)op;
//                }
//            };
//
//            Report *report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusFailed));
//
//            expect(extract.isFinished).to.equal(YES);
//            expect(extract.wasSuccessful).to.equal(NO);
//            expect(multipleExtracts).to.beFalsy();
//
//            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"posts failure notification if extract fails", ^{

            failure(@"todo");

//            [fileManager setWorkingDirChildren:@"blue.zip", nil];
//            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
//            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
//                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
//            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
//            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
//
//            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
//                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
//                    *errOut = [[NSError alloc] initWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"error for test"}];
//                    return nil;
//                };
//            }];
//
//            // intentionally do not enqueue import process to force failure if attempted
//            // TestImportProcess *blueImport = [blueType enqueueImport];
//
//            __block DICEExtractReportOperation *extract;
//            __block BOOL multipleExtracts = NO;
//            importQueue.onAddOperation = ^(NSOperation *op) {
//                if (!NSThread.isMainThread) {
//                    [NSException raise:NSInternalInconsistencyException format:@"queued extract operation from background thread"];
//                }
//                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
//                    if (extract != nil) {
//                        multipleExtracts = YES;
//                        return;
//                    }
//                    extract = (DICEExtractReportOperation *)op;
//                }
//            };
//
//            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:notifications from:store withBlock:nil];
//
//            Report *report = [store attemptToImportReportFromResource:archiveUrl];
//
//            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(1));
//            
//            expect(extract.isFinished).to.equal(YES);
//            expect(extract.wasSuccessful).to.equal(NO);
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//            expect(report.summary).to.equal(@"Failed to extract archive contents");
//
//            ReceivedNotification *received = observer.received.lastObject;
//            NSNotification *note = received.notification;
//
//            expect(received.wasMainThread).to.equal(YES);
//            expect(note.userInfo[@"report"]).to.beIdenticalTo(report);
//            
//            [NSFileHandle deswizzleAllClassMethods];
        });

    });

    describe(@"load all reports", ^{

        beforeEach(^{
        });

        it(@"creates reports for each file in reports directory", ^{

            failure(@"todo");

            //            [fileManager setWorkingDirChildren:@"report1.red", @"report2.blue", @"something.else", nil];
            //
            //            [redType enqueueImport];
            //            [blueType enqueueImport];
            //
            //            NSArray *reports = [store loadReports];
            //
            //            expect(reports).to.haveCountOf(3);
            //            assertThat(reports, hasItems(
            //                hasProperty(@"sourceFile", [reportsDir URLByAppendingPathComponent:@"report1.red"]),
            //                hasProperty(@"sourceFile", [reportsDir URLByAppendingPathComponent:@"report2.blue"]),
            //                hasProperty(@"sourceFile", [reportsDir URLByAppendingPathComponent:@"something.else"]),
            //                nil));
            //
            //            assertWithTimeout(1.0, thatEventually(reports), everyItem(hasProperty(@"isImportFinished", isTrue())));
        });

        it(@"removes reports with path that does not exist and are not importing", ^{

            failure(@"todo");

            //            [fileManager setWorkingDirChildren:@"report1.red", @"report2.blue", nil];
            //
            //            [redType enqueueImport];
            //            [blueType enqueueImport];
            //
            //            NSArray<Report *> *reports = [store loadReports];
            //
            //            assertWithTimeout(1.0, thatEventually(reports), everyItem(hasProperty(@"isEnabled", isTrue())));
            //
            //            expect(reports).to.haveCountOf(2);
            //            expect(reports[0].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            //            expect(reports[1].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            //
            //            [fileManager removeItemAtURL:reports[0].importDir error:nil];
            //
            //            reports = [store loadReports];
            //
            //            expect(reports).to.haveCountOf(1);
            //            expect(reports.firstObject.sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

        it(@"leaves imported and importing reports in order of discovery", ^{

            failure(@"todo");

            //            [fileManager setWorkingDirChildren:@"report1.red", @"report2.blue", @"report3.red", nil];
            //
            //            TestImportProcess *blueImport = [blueType.enqueueImport block];
            //            TestImportProcess *redImport1 = [redType enqueueImport];
            //            TestImportProcess *redImport2 = [redType enqueueImport];
            //
            //            NSArray<Report *> *reports1 = [[store loadReports] copy];
            //
            //            expect(reports1).to.haveCountOf(3);
            //            expect(reports1[0].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            //            expect(reports1[1].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            //            expect(reports1[2].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);
            //
            //            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && redImport2.isFinished)), isTrue());
            //
            //            expect(store.reports[0].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            //            expect(store.reports[1].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            //            expect(store.reports[2].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);
            //
            //            [fileManager removeItemAtURL:store.reports[0].importDir error:nil];
            //            [fileManager createFilePath:@"report11.red" contents:nil];
            //            redImport1 = [redType enqueueImport];
            //
            //            NSArray<Report *> *reports2 = [[store loadReports] copy];
            //
            //            NSIndexSet *bluePos = [reports2 indexesOfObjectsPassingTest:^BOOL(Report * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            //                return [obj.sourceFile isEqual:[reportsDir URLByAppendingPathComponent:@"report2.blue"]];
            //            }];
            //
            //            expect(bluePos).to.haveCountOf(1);
            //            expect(reports2).to.haveCountOf(3);
            //            expect(reports2[0].sourceFile).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            //            assertThat(reports1, hasItem(sameInstance(reports2[0])));
            //            assertThat(reports2, hasItem(hasProperty(@"sourceFile", [reportsDir URLByAppendingPathComponent:@"report3.red"])));
            //            assertThat(reports2, hasItem(hasProperty(@"sourceFile", [reportsDir URLByAppendingPathComponent:@"report11.red"])));
            //
            //            [blueImport unblock];
            //
            //            assertWithTimeout(1.0, thatEventually(reports2), everyItem(hasProperty(@"isEnabled", isTrue())));
        });

        it(@"leaves failed download reports", ^{

            failure(@"todo");

            //            Report *failedDownload = [store attemptToImportReportFromResource:[NSURL URLWithString:@"http://dice.com/leavemebe"]];
            //            DICEDownload *download = [[DICEDownload alloc] initWithUrl:failedDownload.remoteSource];
            //            download.wasSuccessful = NO;
            //            [store downloadManager:downloadManager didFinishDownload:download];
            //
            //            assertWithTimeout(1.0, thatEventually(@(failedDownload.isImportFinished)), isTrue());
            //
            //            expect(failedDownload.importState).to.equal(ReportImportStatusFailed);
            //            expect(store.reports).to.contain(failedDownload);
            //
            //            NSArray<Report *> *loaded = [store loadReports];
            //
            //            expect(loaded).to.haveCountOf(1);
            //            expect(loaded).to.contain(failedDownload);
            //            expect(store.reports).to.haveCountOf(1);
            //            expect(store.reports).to.contain(failedDownload);
        });

        it(@"sends notifications about added reports", ^{

            failure(@"todo");

            //            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportAdded on:notifications from:store withBlock:nil];
            //
            //            [fileManager setWorkingDirChildren:@"report1.red", @"report2.blue", nil];
            //
            //            [[redType enqueueImport] cancelAll];
            //            [[blueType enqueueImport] cancelAll];
            //
            //            NSArray *reports = [store loadReports];
            //
            //            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(2));
            //
            //            [observer.received enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            //                NSNotification *note = [obj notification];
            //                Report *report = note.userInfo[@"report"];
            //
            //                expect(note.name).to.equal(ReportNotification.reportAdded);
            //                expect(report).to.beIdenticalTo(reports[idx]);
            //            }];
            //
            //            [notifications removeObserver:observer];
        });
        
        it(@"posts a reports loaded notification", ^{
            
            failure(@"todo");
            
            //            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportsLoaded on:notifications from:store withBlock:nil];
            //            [store loadReports];
            //
            //            assertWithTimeout(1.0, thatEventually(observer.received), hasCountOf(1));
        });
        
    });

    describe(@"persistence", ^{

        it(@"writes a record to the import dir when the import succeeds", ^{

            failure(@"todo");

//            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"test.blue"];
//            [fileManager setWorkingDirChildren:sourceFile.lastPathComponent, nil];
//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//
//            Report *report = [store attemptToImportReportFromResource:sourceFile];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            NSString *recordPath = [report.importDir.path stringByAppendingPathComponent:@"dice.obj"];
//
//            expect([fileManager fileExistsAtPath:recordPath]).to.beFalsy();
//
//            [blueImport unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect([fileManager fileExistsAtPath:recordPath]).to.beTruthy();
//            expect(report.importState).to.equal(ReportImportStatusSuccess);
//
//            NSData *record = [fileManager contentsAtPath:recordPath];
//            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:record];
//            Report *fromRecord = [[Report alloc] initWithCoder:unarchiver];
//            [unarchiver finishDecoding];
//
//            expect(fromRecord.baseDir).to.equal(report.baseDir);
//            expect(fromRecord.importDir).to.equal(report.importDir);
//            expect(fromRecord.importState).to.equal(report.importState);
//            expect(fromRecord.isEnabled).to.equal(report.isEnabled);
//            expect(fromRecord.rootFile).to.equal(report.rootFile);
//            expect(fromRecord.sourceFile).to.equal(report.sourceFile);
//            expect(fromRecord.statusMessage).to.equal(report.statusMessage);
//            expect(fromRecord.summary).to.equal(report.summary);
//            expect(fromRecord.title).to.equal(report.title);
        });

        it(@"writes a record to the import dir when the import fails", ^{

            failure(@"todo");

//            NSURL *sourceFile = [reportsDir URLByAppendingPathComponent:@"test.blue"];
//            [fileManager setWorkingDirChildren:sourceFile.lastPathComponent, nil];
//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//            [blueImport.steps.lastObject cancel];
//
//            Report *report = [store attemptToImportReportFromResource:sourceFile];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToUnsignedInteger(ReportImportStatusImporting));
//
//            NSString *recordPath = [report.importDir.path stringByAppendingPathComponent:@"dice.obj"];
//
//            expect([fileManager fileExistsAtPath:recordPath]).to.beFalsy();
//
//            [blueImport unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            expect([fileManager fileExistsAtPath:recordPath]).to.beTruthy();
//            expect(report.importState).to.equal(ReportImportStatusFailed);
//
//            NSData *record = [fileManager contentsAtPath:recordPath];
//            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:record];
//            Report *fromRecord = [[Report alloc] initWithCoder:unarchiver];
//            [unarchiver finishDecoding];
//
//            expect(fromRecord.baseDir).to.equal(report.baseDir);
//            expect(fromRecord.importDir).to.equal(report.importDir);
//            expect(fromRecord.importState).to.equal(report.importState);
//            expect(fromRecord.isEnabled).to.equal(report.isEnabled);
//            expect(fromRecord.rootFile).to.equal(report.rootFile);
//            expect(fromRecord.sourceFile).to.equal(report.sourceFile);
//            expect(fromRecord.statusMessage).to.equal(report.statusMessage);
//            expect(fromRecord.summary).to.equal(report.summary);
//            expect(fromRecord.title).to.equal(report.title);
        });

        it(@"restores persisted record from dice.obj in import dir", ^{

            failure(@"todo");

//            Report *report = [[Report alloc] init];
//            report.sourceFile = [reportsDir URLByAppendingPathComponent:@"restore.zip"];
//            report.importDir = [reportsDir URLByAppendingPathComponent:@"restore.dice_import" isDirectory:YES];
//            report.baseDir = [report.importDir URLByAppendingPathComponent:@"dice_content"];
//            report.rootFile = [report.baseDir URLByAppendingPathComponent:@"index.blue"];
//            report.uti = @"dice.test.blue";
//            report.title = @"Persistence Test";
//            report.summary = @"Persisted content";
//            report.importState = ReportImportStatusSuccess;
//
//            NSMutableData *record = [NSMutableData data];
//            NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:record];
//            [report encodeWithCoder:archiver];
//            [archiver finishEncoding];
//
//            [fileManager createFilePath:@"restore.dice_import/dice_content/index.blue" contents:[@"Restore me!" dataUsingEncoding:NSUTF8StringEncoding]];
//            [fileManager createFilePath:@"restore.dice_import/dice.obj" contents:record];
//
//            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:ReportNotification.reportImportFinished on:store.notifications from:store withBlock:nil];
//
//            Report *restored = [store attemptToImportReportFromResource:report.importDir];
//
//            expect(restored.importState).to.equal(ReportImportStatusNewLocal);
//            expect(store.reports).to.haveCountOf(1);
//            expect(store.reports).to.contain(restored);
//            expect(observer.received).to.haveCountOf(0);
//
//            assertWithTimeout(1.0, thatEventually(@(restored.isImportFinished)), isTrue());
//
//            expect(store.reports).to.haveCountOf(1);
//            expect(store.reports).to.contain(restored);
//            expect(restored.sourceFile).to.equal(report.sourceFile);
//            expect(restored.importDir).to.equal(report.importDir);
//            expect(restored.baseDir).to.equal(report.baseDir);
//            expect(restored.rootFile).to.equal(report.rootFile);
//            expect(restored.uti).to.equal(report.uti);
//            expect(restored.title).to.equal(report.title);
//            expect(restored.summary).to.equal(report.summary);
//            expect(restored.importState).to.equal(ReportImportStatusSuccess);
//            expect(observer.received).to.haveCountOf(1);
//            expect(observer.received.firstObject.wasMainThread).to.beTruthy();
//            expect(observer.received.firstObject.userInfo[@"report"]).to.beIdenticalTo(restored);
        });


        it(@"correlates download messages to persisted records before they are loaded", ^{

            failure(@"todo");

//            NSURL *downloadUrl = [NSURL URLWithString:@"http://dice.com/test.blue"];
//            Report *previouslyStartedDownload = [[Report alloc] init];
//            previouslyStartedDownload.remoteSource = downloadUrl;
//            previouslyStartedDownload.importState = ReportImportStatusDownloading;
//            previouslyStartedDownload.importDir = [reportsDir URLByAppendingPathComponent:@"test.dice_import"];
//
//            NSMutableData *record = [NSMutableData data];
//            NSKeyedArchiver *coder = [[NSKeyedArchiver alloc] initForWritingWithMutableData:record];
//            [previouslyStartedDownload encodeWithCoder:coder];
//
//            [fileManager createFilePath:@"test.dice_import/dice.obj" contents:record];
//
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:downloadUrl];
//            download.bytesExpected = 999999;
//            download.bytesReceived = 888888;
//            download.httpResponseCode = 200;
//            [store downloadManager:downloadManager didReceiveDataForDownload:download];
//
//            expect(store.reports).to.haveCount(1);
//
//            Report *report = store.reports.firstObject;
//
//            expect(report.remoteSource).to.equal(downloadUrl);
//
//            [store loadReports];
//
//            expect(store.reports).to.haveCount(1);
//            expect(store.reports.firstObject).to.beIdenticalTo(report);
        });
    });

#pragma mark - Downloading

    describe(@"downloading content", ^{

        it(@"starts a download when importing from an http url", ^{

            failure(@"todo");

//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report"];
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            [verify(downloadManager) downloadUrl:url];
//            expect(report.importState).to.equal(ReportImportStatusDownloading);
//            expect(store.reports).to.contain(report);
        });

        it(@"starts a download when importing from an https url", ^{

            failure(@"todo");

//            NSURL *url = [NSURL URLWithString:@"https://dice.com/report"];
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            [verify(downloadManager) downloadUrl:url];
//            expect(report.importState).to.equal(ReportImportStatusDownloading);
//            expect(store.reports).to.contain(report);
        });

        it(@"saves a report before the download begins", ^{
            failure(@"do it");
        });

        it(@"posts a report added notification before the download begins", ^{

            failure(@"todo");

//            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportAdded on:store.notifications from:store withBlock:nil];
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            assertWithTimeout(1.0, thatEventually(obs.received), hasCountOf(1));
//
//            ReceivedNotification *received = obs.received.firstObject;
//            NSNotification *note = received.notification;
//            NSDictionary *userInfo = note.userInfo;
//
//            expect(userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.importState).to.equal(ReportImportStatusDownloading);
        });

        it(@"posts download progress notifications", ^{

            failure(@"todo");

//            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:nil];
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            download.bytesReceived = 12345;
//            Report *report = [store attemptToImportReportFromResource:url];
//            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];
//
//            expect(obs.received).to.haveCountOf(1);
//
//            ReceivedNotification *received = obs.received.firstObject;
//            NSNotification *note = received.notification;
//            NSDictionary *userInfo = note.userInfo;
//
//            expect(userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.downloadProgress).to.equal(1);
        });

        it(@"posts download finished notification", ^{

            failure(@"todo");

//            TestImportProcess *import = [blueType enqueueImport];
//            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadComplete on:store.notifications from:store withBlock:nil];
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            download.bytesReceived = 999999;
//            download.downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:download.downloadedFile];
//            download.wasSuccessful = YES;
//            [fileManager createFilePath:download.downloadedFile.path contents:nil];
//            [store downloadManager:store.downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(import.isFinished)), isTrue());
//
//            ReceivedNotification *received = obs.received.firstObject;
//            NSNotification *note = received.notification;
//            NSDictionary *userInfo = note.userInfo;
//
//            expect(obs.received).to.haveCountOf(1);
//            expect(userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.downloadProgress).to.equal(100);
        });

        it(@"does not post a progress notification if the percent complete did not change", ^{

            failure(@"todo");

//            __block NSInteger lastProgress = 0;
//            NotificationRecordingObserver *obs = [[NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:^(NSNotification *notification) {
//                if (![ReportNotification.reportDownloadProgress isEqualToString:notification.name]) {
//                    return;
//                }
//                Report *report = notification.userInfo[@"report"];
//                if (lastProgress == report.downloadProgress) {
//                    failure([NSString stringWithFormat:@"duplicate progress notifications: %@", @(lastProgress)]);
//                }
//                lastProgress = report.downloadProgress;
//            }] observe:ReportNotification.reportDownloadComplete on:store.notifications from:store];
//
//            TestImportProcess *import = [blueType enqueueImport];
//            import.steps = @[[NSBlockOperation blockOperationWithBlock:^{}]];
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            Report *report = [store attemptToImportReportFromResource:url];
//
//            download.bytesReceived = 12345;
//            [store downloadManager:downloadManager didReceiveDataForDownload:download];
//            download.bytesReceived = 12500;
//            [store downloadManager:downloadManager didReceiveDataForDownload:download];
//            download.bytesReceived = 99999;
//            [store downloadManager:downloadManager didReceiveDataForDownload:download];
//            download.bytesReceived = 999999;
//            [store downloadManager:downloadManager didReceiveDataForDownload:download];
//
//            download.downloadedFile = [reportsDir URLByAppendingPathComponent:@"report.blue"];
//            [store downloadManager:downloadManager willFinishDownload:download movingToFile:download.downloadedFile];
//            download.wasSuccessful = YES;
//            [store downloadManager:downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(report.isImportFinished)), isTrue());
//
//            ReceivedNotification *received = obs.received.lastObject;
//            NSNotification *note = received.notification;
//            NSDictionary *userInfo = note.userInfo;
//
//            expect(obs.received).to.haveCountOf(4);
//            expect(obs.received.lastObject.notification.name).to.equal(ReportNotification.reportDownloadComplete);
//            expect(userInfo[@"report"]).to.beIdenticalTo(report);
//            expect(report.downloadProgress).to.equal(100);
        });

        it(@"posts a progress notification about a url that did not match a report", ^{

            failure(@"todo");

//            NotificationRecordingObserver *obs = [NotificationRecordingObserver observe:ReportNotification.reportDownloadProgress on:store.notifications from:store withBlock:nil];
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            download.bytesReceived = 999999;
//            [store attemptToImportReportFromResource:url];
//            DICEDownload *foreignDownload = [[DICEDownload alloc] initWithUrl:[NSURL URLWithString:@"http://not.a.report/i/know/about.blue"]];
//
//            [store downloadManager:store.downloadManager didReceiveDataForDownload:foreignDownload];
//            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];
//
//            expect(obs.received).to.haveCountOf(2);
        });

        it(@"begins an import for the same report after the download is complete", ^{

            failure(@"todo");

//            TestImportProcess *blueImport = [[blueType enqueueImport] block];
//            NSURL *url = [NSURL URLWithString:@"http://dice.com/report.blue"];
//            DICEDownload *download = [[DICEDownload alloc] initWithUrl:url];
//            download.bytesExpected = 999999;
//            Report *report = [store attemptToImportReportFromResource:url];
//            download.bytesReceived = 555555;
//            [store downloadManager:store.downloadManager didReceiveDataForDownload:download];
//            download.bytesReceived = 999999;
//            url = [reportsDir URLByAppendingPathComponent:@"report.blue"];
//            [store downloadManager:store.downloadManager willFinishDownload:download movingToFile:url];
//            [fileManager createFileAtPath:url.path contents:nil attributes:@{NSFileType: NSFileTypeRegular}];
//            download.wasSuccessful = YES;
//            download.downloadedFile = url;
//            [store downloadManager:store.downloadManager didFinishDownload:download];
//
//            assertWithTimeout(1.0, thatEventually(@(report.importState)), equalToInteger(ReportImportStatusImporting));
//
//            expect(blueImport.report).to.beIdenticalTo(report);
//
//            [blueImport unblock];
//
//            assertWithTimeout(1.0, thatEventually(@(blueImport.isFinished)), isTrue());
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
