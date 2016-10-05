#import "Report.h"
#import "Specta.h"
#import <Expecta/Expecta.h>

#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <JGMethodSwizzler/JGMethodSwizzler.h>

#import "DICEArchive.h"
#import "DICEExtractReportOperation.h"
#import "ImportProcess+Internal.h"
#import "NotificationRecordingObserver.h"
#import "NSOperation+Blockable.h"
#import "ReportStore.h"
#import "ReportType.h"
#import "TestDICEArchive.h"
#import "TestOperationQueue.h"
#import "TestReportType.h"
#import "DICEUtiExpert.h"


@interface ReportStoreSpec_FileManager : NSFileManager

@property NSURL *reportsDir;
@property NSMutableArray<NSString *> *pathsInReportsDir;
@property NSMutableDictionary *pathAttrs;
@property BOOL (^createFileAtPathBlock)(NSString *path);
@property BOOL (^createDirectoryAtUrlBlock)(NSURL *path, BOOL createIntermediates, NSError **error);

- (void)setContentsOfReportsDir:(NSString *)relPath, ... NS_REQUIRES_NIL_TERMINATION;

@end

@implementation ReportStoreSpec_FileManager

- (instancetype)init
{
    self = [super init];
    self.pathsInReportsDir = [NSMutableArray array];
    self.pathAttrs = [NSMutableDictionary dictionary];
    return self;
}

- (NSString *)pathRelativeToReportsDirOfPath:(NSString *)absolutePath
{
    NSArray *reportsDirParts = self.reportsDir.pathComponents;
    NSArray *pathParts = absolutePath.pathComponents;
    NSArray *pathReportsDirParts = [pathParts subarrayWithRange:NSMakeRange(0, reportsDirParts.count)];
    NSArray *pathRelativeParts = [pathParts subarrayWithRange:NSMakeRange(reportsDirParts.count, pathParts.count - reportsDirParts.count)];
    if ([pathReportsDirParts isEqualToArray:reportsDirParts]) {
        return [pathRelativeParts componentsJoinedByString:@"/"];
    }
    return nil;
}

- (BOOL)fileExistsAtPath:(NSString *)path
{
    @synchronized (self) {
        NSString *relPath = [self pathRelativeToReportsDirOfPath:path];
        return relPath != nil && [self.pathsInReportsDir containsObject:relPath];
    }
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory
{
    @synchronized (self) {
        if (![self fileExistsAtPath:path]) {
            *isDirectory = NO;
            return NO;
        }
        NSString *relPath = [self pathRelativeToReportsDirOfPath:path];
        *isDirectory = self.pathAttrs[relPath] && [self.pathAttrs[relPath][NSFileType] isEqualToString:NSFileTypeDirectory];
        return YES;
    }
}

- (NSArray *)contentsOfDirectoryAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray<NSString *> *)keys options:(NSDirectoryEnumerationOptions)mask error:(NSError **)error
{
    @synchronized (self) {
        NSMutableArray *paths = [NSMutableArray array];
        for (NSString *relPath in self.pathsInReportsDir) {
            if (relPath.pathComponents.count == 1) {
                BOOL isDir = [NSFileTypeDirectory isEqualToString:self.pathAttrs[relPath][NSFileType]];
                NSURL *url = [self.reportsDir URLByAppendingPathComponent:relPath isDirectory:isDir];
                [paths addObject:url];
            }
        }
        return paths;
    }
}

- (void)setContentsOfReportsDir:(NSString *)relPath, ...
{
    @synchronized (self) {
        [self.pathsInReportsDir removeAllObjects];
        [self.pathAttrs removeAllObjects];
        if (relPath == nil) {
            return;
        }
        va_list args;
        va_start(args, relPath);
        for(NSString *arg = relPath; arg != nil; arg = va_arg(args, NSString *)) {
            [self addPathInReportsDir:arg withAttributes:nil];
        }
        va_end(args);
    }
}

- (void)addPathInReportsDir:(NSString *)relPath withAttributes:(NSDictionary *)attrs
{
    @synchronized (self) {
        if (!attrs) {
            attrs = @{};
        }
        NSMutableDictionary *mutableAttrs = [NSMutableDictionary dictionaryWithDictionary:attrs];
        if ([relPath hasSuffix:@"/"]) {
            relPath = [relPath stringByReplacingCharactersInRange:NSMakeRange(relPath.length - 1, 1) withString:@""];
            if (!mutableAttrs[NSFileType]) {
                mutableAttrs[NSFileType] = NSFileTypeDirectory;
            }
        }
        else {
            if (!mutableAttrs[NSFileType]) {
                mutableAttrs[NSFileType] = NSFileTypeRegular;
            }
        }
        [self.pathsInReportsDir addObject:relPath];
        self.pathAttrs[relPath] = [NSDictionary dictionaryWithDictionary:mutableAttrs];
    }
}

- (BOOL)createFileAtPath:(NSString *)path contents:(NSData *)data attributes:(NSDictionary<NSString *, id> *)attr
{
    @synchronized (self) {
        if (self.createFileAtPathBlock) {
            return self.createFileAtPathBlock(path);
        }
        BOOL isDir;
        if ([self fileExistsAtPath:path isDirectory:&isDir]) {
            return !isDir;
        }
        NSString *relPath = [self pathRelativeToReportsDirOfPath:path];
        if (relPath == nil) {
            return NO;
        }
        [self addPathInReportsDir:relPath withAttributes:attr];
        return YES;
    }
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSString *, id> *)attributes error:(NSError **)error
{
    return [self createDirectoryAtURL:[NSURL fileURLWithPath:path isDirectory:YES] withIntermediateDirectories:createIntermediates attributes:attributes error:error];
}

- (BOOL)createDirectoryAtURL:(NSURL *)url withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSString *, id> *)attributes error:(NSError **)error
{
    @synchronized (self) {
        if (self.createDirectoryAtUrlBlock) {
            return self.createDirectoryAtUrlBlock(url, createIntermediates, error);
        }
        BOOL isDir;
        if ([self fileExistsAtPath:url.path isDirectory:&isDir]) {
            return isDir && createIntermediates;
        }
        NSString *relPath = [self pathRelativeToReportsDirOfPath:url.path];
        [self addPathInReportsDir:relPath withAttributes:@{NSFileType: NSFileTypeDirectory}];
        return YES;
    }
}

- (BOOL)removeItemAtURL:(NSURL *)URL error:(NSError * _Nullable __autoreleasing *)error
{
    @synchronized (self) {
        NSString *relativePath = [self pathRelativeToReportsDirOfPath:URL.path];
        if (relativePath == nil) {
            return NO;
        }
        NSUInteger index = [self.pathsInReportsDir indexOfObject:relativePath];
        if (index == NSNotFound) {
            return NO;
        }
        [self.pathsInReportsDir removeObjectAtIndex:index];
        return YES;
    }
}

@end

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


SpecBegin(ReportStore)

describe(@"ReportStore_FileManager", ^{

    __block ReportStoreSpec_FileManager *fileManager;
    __block NSURL *reportsDir;

    beforeEach(^{
        fileManager = [[ReportStoreSpec_FileManager alloc] init];
        fileManager.reportsDir = reportsDir = [NSURL fileURLWithPath:@"/dice" isDirectory:YES];
    });

    it(@"works", ^{
        [fileManager setContentsOfReportsDir:@"hello.txt", @"dir/", nil];

        BOOL isDir;
        BOOL *isDirOut = &isDir;

        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"hello.txt"].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(NO);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"dir" isDirectory:YES].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(YES);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"dir"].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(YES);

        expect(fileManager.pathsInReportsDir).to.contain(@"dir");
        expect([fileManager removeItemAtURL:[reportsDir URLByAppendingPathComponent:@"does_not_exist"] error:NULL]).to.equal(NO);
        expect([fileManager removeItemAtURL:[reportsDir URLByAppendingPathComponent:@"dir"] error:NULL]).to.equal(YES);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"dir"].path]).to.equal(NO);
        expect(fileManager.pathsInReportsDir).notTo.contain(@"dir");

        expect([fileManager createFileAtPath:[reportsDir URLByAppendingPathComponent:@"new.txt"].path contents:nil attributes:nil]).to.equal(YES);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"new.txt"].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(NO);
        NSUInteger pathCount = fileManager.pathsInReportsDir.count;
        expect([fileManager createFileAtPath:[reportsDir.path stringByAppendingPathComponent:@"new.txt"] contents:nil attributes:nil]).to.equal(YES);
        expect([fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"new.txt"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.equal(NO);
        expect(fileManager.pathsInReportsDir.count).to.equal(pathCount);

        expect([fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.equal(YES);
        expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"dir"].path isDirectory:isDirOut]).to.equal(YES);
        expect(isDir).to.equal(YES);
        pathCount = fileManager.pathsInReportsDir.count;
        expect([fileManager createFileAtPath:[reportsDir.path stringByAppendingPathComponent:@"dir"] contents:nil attributes:nil]).to.equal(NO);
        expect([fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:YES attributes:nil error:NULL]).to.equal(YES);
        expect([fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"dir"] withIntermediateDirectories:NO attributes:nil error:NULL]).to.equal(NO);
        expect(fileManager.pathsInReportsDir.count).to.equal(pathCount);

        expect([fileManager createFileAtPath:@"/not/in/reportsDir.txt" contents:nil attributes:nil]).to.equal(NO);
        expect([fileManager fileExistsAtPath:@"/not/in/reportsDir.txt" isDirectory:isDirOut]).to.equal(NO);
        expect(isDir).to.equal(NO);
    });

});

describe(@"NSFileManager", ^{

    it(@"returns directory url with trailing slash", ^{
        NSURL *resources = [[[NSBundle bundleForClass:[self class]] bundleURL] URLByAppendingPathComponent:@"resources" isDirectory:YES];
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

describe(@"ReportStore", ^{

    __block TestReportType *redType;
    __block TestReportType *blueType;
    __block ReportStoreSpec_FileManager *fileManager;
    __block id<DICEArchiveFactory> archiveFactory;
    __block TestOperationQueue *importQueue;
    __block NSNotificationCenter *notifications;
    __block ReportStore *store;
    __block UIApplication *app;

    NSURL *reportsDir = [NSURL fileURLWithPath:@"/dice/reports"];

    beforeAll(^{
    });

    beforeEach(^{
        fileManager = [[ReportStoreSpec_FileManager alloc] init];
        fileManager.reportsDir = reportsDir;
        archiveFactory = mockProtocol(@protocol(DICEArchiveFactory));
        importQueue = [[TestOperationQueue alloc] init];
        notifications = [[NSNotificationCenter alloc] init];
        app = mock([UIApplication class]);

        redType = [[TestReportType alloc] initWithExtension:@"red"];
        blueType = [[TestReportType alloc] initWithExtension:@"blue"];

        // initialize a new ReportStore to ensure all tests are independent
        store = [[ReportStore alloc] initWithReportsDir:reportsDir
            utiExpert:[[DICEUtiExpert alloc] init]
            archiveFactory:archiveFactory
            importQueue:importQueue
            fileManager:fileManager
            notifications:notifications
            application:app];

        store.reportTypes = @[
            redType,
            blueType
        ];
    });

    afterEach(^{
        [importQueue waitUntilAllOperationsAreFinished];
        stopMocking(archiveFactory);
        stopMocking(app);
        fileManager = nil;
    });

    afterAll(^{
        
    });

    describe(@"loadReports", ^{

        beforeEach(^{
        });

        it(@"creates reports for each file in reports directory", ^{
            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", @"something.else", nil];

            id redImport = [redType enqueueImport];
            id blueImport = [blueType enqueueImport];

            NSArray *reports = [store loadReports];

            expect(reports.count).to.equal(3);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(((Report *)reports[2]).url).to.equal([reportsDir URLByAppendingPathComponent:@"something.else"]);

            assertWithTimeout(1.0, thatEventually(@([redImport isFinished] && [blueImport isFinished])), isTrue());
        });

        it(@"removes reports with path that does not exist and are not importing", ^{
            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", nil];

            TestImportProcess *redImport = redType.enqueueImport;
            TestImportProcess *blueImport = blueType.enqueueImport;

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled && blueImport.report.isEnabled)), isTrue());

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            [fileManager setContentsOfReportsDir:@"report2.blue", nil];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
        });

        it(@"leaves imported and importing reports in order of discovery", ^{

            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", @"report3.red", nil];

            TestImportProcess *blueImport = [blueType.enqueueImport block];
            TestImportProcess *redImport1 = [redType enqueueImport];
            TestImportProcess *redImport2 = [redType enqueueImport];

            NSArray<Report *> *reports1 = [NSArray arrayWithArray:[store loadReports]];

            expect(reports1.count).to.equal(3);
            expect(reports1[0].url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(reports1[1].url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(reports1[2].url).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);

            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && redImport2.isFinished)), isTrue());

            [fileManager setContentsOfReportsDir:@"report2.blue", @"report3.red", @"report11.red", nil];
            redImport1 = [redType enqueueImport];

            NSArray<Report *> *reports2 = [NSArray arrayWithArray:[store loadReports]];

            expect(reports2.count).to.equal(3);
            expect(reports2[0].url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);
            expect(reports2[0]).to.beIdenticalTo(reports1[1]);
            expect(reports2[1].url).to.equal([reportsDir URLByAppendingPathComponent:@"report3.red"]);
            expect(reports2[1]).to.beIdenticalTo(reports1[2]);
            expect(reports2[2].url).to.equal([reportsDir URLByAppendingPathComponent:@"report11.red"]);
            expect(reports2[2]).notTo.beIdenticalTo(reports1[0]);

            [blueImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport1.isFinished && blueImport.report.isEnabled)), isTrue());
        });

        it(@"leaves reports whose path may not exist but are still importing", ^{

            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", nil];

            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSArray<Report *> *reports = [store loadReports];

            expect(reports.count).to.equal(2);
            expect(((Report *)reports[0]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.red"]);
            expect(((Report *)reports[1]).url).to.equal([reportsDir URLByAppendingPathComponent:@"report2.blue"]);

            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(redImport.isFinished).to.equal(NO);
            expect([reports[0] isEnabled]).to.equal(NO);
            expect([reports[1] isEnabled]).to.equal(YES);

            Report *redReport = redImport.report;
            redReport.url = [reportsDir URLByAppendingPathComponent:@"report1.transformed"];

            [fileManager setContentsOfReportsDir:@"report1.transformed", nil];

            reports = [store loadReports];

            expect(reports.count).to.equal(1);
            expect(((Report *)reports.firstObject).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.transformed"]);
            expect(((Report *)reports.firstObject).isEnabled).to.equal(NO);

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            expect(store.reports.count).to.equal(1);
            expect(((Report *)store.reports.firstObject).url).to.equal([reportsDir URLByAppendingPathComponent:@"report1.transformed"]);
            expect(((Report *)store.reports.firstObject).isEnabled).to.equal(YES);
        });

        it(@"sends notifications about added reports", ^{

            NSNotificationCenter *notifications = store.notifications;

            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            [fileManager setContentsOfReportsDir:@"report1.red", @"report2.blue", nil];

            [redType.enqueueImport cancelAll];
            [blueType.enqueueImport cancelAll];

            NSArray *reports = [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(2));

            [observer.received enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSNotification *note = [obj notification];
                Report *report = note.userInfo[@"report"];

                expect(note.name).to.equal([ReportNotification reportAdded]);
                expect(report).to.beIdenticalTo(reports[idx]);
            }];

            [notifications removeObserver:observer];
        });

    });

    describe(@"attemptToImportReportFromResource", ^{

        it(@"imports a report with the capable ReportType", ^{

            TestImportProcess *redImport = redType.enqueueImport;

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());
            expect(redImport).toNot.beNil;
        });

        it(@"returns a report even if the url cannot be imported", ^{
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(report).notTo.beNil();
            expect(report.url).to.equal(url);
        });

        it(@"assigns an error message if the report type was unknown", ^{
            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.green"];
            Report *report = [store attemptToImportReportFromResource:url];

            assertWithTimeout(1.0, thatEventually(report.error), isNot(nilValue()));
        });

        it(@"adds the initial report to the report list", ^{
            TestImportProcess *import = [redType.enqueueImport block];

            NSURL *url = [reportsDir URLByAppendingPathComponent:@"report.red"];
            Report *report = [store attemptToImportReportFromResource:url];

            expect(store.reports).to.contain(report);
            expect(report.reportID).to.beNil();
            expect(report.title).to.equal(report.url.lastPathComponent);
            expect(report.summary).to.equal(@"Importing...");
            expect(report.error).to.beNil();
            expect(report.isEnabled).to.equal(NO);

            [import unblock];

            [importQueue waitUntilAllOperationsAreFinished];
        });

        it(@"sends a notification about adding the report", ^{
            NSNotificationCenter *notifications = store.notifications;
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            [redType enqueueImport];

            Report *report = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"report1.red"]];

            [importQueue waitUntilAllOperationsAreFinished];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            ReceivedNotification *received = observer.received.firstObject;
            Report *receivedReport = received.notification.userInfo[@"report"];

            expect(received.notification.name).to.equal([ReportNotification reportAdded]);
            expect(receivedReport).to.beIdenticalTo(report);

            [notifications removeObserver:observer];
        });

        it(@"does not start an import for a report file it is already importing", ^{
            TestImportProcess *import = [redType.enqueueImport block];

            NSNotificationCenter *notifications = store.notifications;
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportAdded] on:notifications from:store withBlock:nil];

            NSURL *reportUrl = [reportsDir URLByAppendingPathComponent:@"report1.red"];
            Report *report = [store attemptToImportReportFromResource:reportUrl];

            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(report);
            expect(store.reports.firstObject).to.beIdenticalTo(notificationReport);
            expect(store.reports.count).to.equal(1);

            notificationReport = nil;
            [observer.received removeAllObjects];

            Report *sameReport = [store attemptToImportReportFromResource:reportUrl];

            [import unblock];

            assertWithTimeout(1.0, thatEventually(@(report.isEnabled)), isTrue());

            expect(sameReport).to.beIdenticalTo(report);
            expect(store.reports.count).to.equal(1);
            expect(observer.received.count).to.equal(0);

            [notifications removeObserver:observer];
        });

        it(@"enables the report when the import finishes", ^{
            Report *report = mock([Report class]);
            TestImportProcess *import = [[TestImportProcess alloc] initWithReport:report];
            import.steps = @[[[NSOperation alloc] init]];
            [import.steps.firstObject start];

            __block BOOL enabledOnMainThread = NO;
            [givenVoid([report setIsEnabled:YES]) willDo:^id(NSInvocation *invocation) {
                BOOL enabled = NO;
                [invocation getArgument:&enabled atIndex:2];
                enabledOnMainThread = enabled && [NSThread isMainThread];
                return nil;
            }];

            [store importDidFinishForImportProcess:import];

            assertWithTimeout(1.0, thatEventually(@(enabledOnMainThread)), isTrue());
        });

        it(@"sends a notification when the import finishes", ^{

            NSNotificationCenter *notifications = store.notifications;
            NotificationRecordingObserver *observer = [NotificationRecordingObserver observe:[ReportNotification reportImportFinished] on:notifications from:store withBlock:nil];

            TestImportProcess *redImport = [redType enqueueImport];
            Report *importReport = [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());
            assertWithTimeout(1.0, thatEventually(@(observer.received.count)), equalToInteger(1));

            Report *notificationReport = observer.received.firstObject.notification.userInfo[@"report"];
            expect(notificationReport).to.beIdenticalTo(importReport);

            [notifications removeObserver:observer];
        });

        it(@"does not create multiple reports while the archive is extracting", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
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
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    NSLog(@"blocking extract operation");
                    [extract block];
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            NSArray *reports1 = [[store loadReports] copy];

            expect(reports1.count).to.equal(1);

            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());

            NSUInteger opCount = importQueue.operationCount;

            NSArray *reports2 = [[store loadReports] copy];

            expect(reports2.count).to.equal(reports1.count);
            expect(importQueue.operationCount).to.equal(opCount);

            TestImportProcess *blueImport = [blueType enqueueImport];

            NSLog(@"unblocking extract operation");
            [extract unblock];
            
            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
            
            [NSFileHandle deswizzleAllClassMethods];
        });

    });

    describe(@"importing report archives", ^{

        it(@"creates a base dir if the archive has no base dir", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dicex" isDirectory:YES];
            [fileManager setCreateDirectoryAtUrlBlock:^BOOL(NSURL *url, BOOL intermediates, NSError **error) {
                expect(url).to.equal(baseDir);
                return [url isEqual:baseDir];
            }];
            [fileManager setCreateFileAtPathBlock:^BOOL(NSString *path) {
                expect(path).to.equal([baseDir.path stringByAppendingPathComponent:@"index.blue"]);
                return [path isEqualToString:[baseDir.path stringByAppendingPathComponent:@"index.blue"]];
            }];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not create a new base dir if archive has base dir", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];

            [fileManager setCreateDirectoryAtUrlBlock:^BOOL(NSURL *path, BOOL intermediates, NSError **error) {
                expect(path).to.equal(baseDir);
                return [path isEqual:baseDir];
            }];
            [fileManager setCreateFileAtPathBlock:^BOOL(NSString *path) {
                expect(path).to.equal([baseDir.path stringByAppendingPathComponent:@"index.blue"]);
                return [path isEqualToString:[baseDir.path stringByAppendingPathComponent:@"index.blue"]];
            }];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes the report url to the extracted base dir", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/" sizeInArchive:0 sizeExtracted:0],
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];
            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue_base" isDirectory:YES];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(blueImport.report.url).to.equal(baseDir);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"changes the report url to the created base dir", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSURL *baseDir = [reportsDir URLByAppendingPathComponent:@"blue.zip.dicex" isDirectory:YES];
            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            expect(blueImport.report.url).to.equal(baseDir);

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"removes the archive file after extracting the contents", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];
            TestImportProcess *blueImport = [blueType enqueueImport];

            NSFileHandle *handle = mock([NSFileHandle class]);
            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    return handle;
                };
            }];

            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.equal(YES);

            [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());
            
            expect([fileManager fileExistsAtPath:[reportsDir URLByAppendingPathComponent:@"blue.zip"].path]).to.equal(NO);
            
            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"posts notifications about extract progress", ^{
            failure(@"do it");
        });

        it(@"does not create multiple reports while the archive is extracting", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
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
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    NSLog(@"blocking extract operation");
                    [extract block];
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            Report *report1 = [store attemptToImportReportFromResource:archiveUrl];

            assertWithTimeout(1.0, thatEventually(@(extract && extract.isExecuting)), isTrue());

            NSUInteger opCount = importQueue.operationCount;

            Report *report2 = [store attemptToImportReportFromResource:archiveUrl];

            expect(report2).to.beIdenticalTo(report1);
            expect(store.reports.count).to.equal(1);
            expect(importQueue.operationCount).to.equal(opCount);

            TestImportProcess *blueImport = [blueType enqueueImport];
            // [blueImport block];
            NSLog(@"unblocking extract operation");
            [extract unblock];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [NSFileHandle deswizzleAllClassMethods];
        });

        it(@"does not start an import process if the extraction fails", ^{
            [fileManager setContentsOfReportsDir:@"blue.zip", nil];
            NSURL *archiveUrl = [reportsDir URLByAppendingPathComponent:@"blue.zip"];
            TestDICEArchive *archive = [TestDICEArchive archiveWithEntries:@[
                [TestDICEArchiveEntry entryWithName:@"blue_base/index.blue" sizeInArchive:100 sizeExtracted:200]
            ] archiveUrl:archiveUrl archiveUti:kUTTypeZipArchive];
            [given([archiveFactory createArchiveForResource:archiveUrl withUti:kUTTypeZipArchive]) willReturn:archive];

            [NSFileHandle swizzleClassMethod:@selector(fileHandleForWritingToURL:error:) withReplacement:JGMethodReplacementProviderBlock {
                return JGMethodReplacement(NSFileHandle *, const Class *, NSURL *url, NSError **errOut) {
                    *errOut = [[NSError alloc] initWithDomain:@"dice.test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"error for test"}];
                    return nil;
                };
            }];

            NSOperation *failStep = [NSBlockOperation blockOperationWithBlock:^{
                failure(@"erroneous import process started");
            }];
            TestImportProcess *blueImport = [blueType enqueueImport];
            blueImport.steps = @[failStep];

            __block DICEExtractReportOperation *extract;
            importQueue.onAddOperation = ^(NSOperation *op) {
                if ([op isKindOfClass:[DICEExtractReportOperation class]]) {
                    if (extract != nil) {
                        failure(@"multiple extract operations queued for the same report archive");
                        return;
                    }
                    extract = (DICEExtractReportOperation *)op;
                    [fileManager createDirectoryAtURL:[reportsDir URLByAppendingPathComponent:@"blue_base"] withIntermediateDirectories:YES attributes:nil error:NULL];
                }
            };

            Report *report = [store attemptToImportReportFromResource:archiveUrl];
            
            assertWithTimeout(1.0, thatEventually(@(extract && extract.isFinished)), isTrue());
            assertWithTimeout(1.0, thatEventually(report.error), notNilValue());

            expect(extract.wasSuccessful).to.equal(NO);
        });

    });

    describe(@"background task handling", ^{

        it(@"starts and ends background task for importing reports", ^{
            [fileManager setContentsOfReportsDir:@"test.red", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:notNilValue() forArgument:1] willReturnUnsignedInteger:999];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [verify(app) endBackgroundTask:999];
        });

        it(@"begins and ends only one background task for multiple concurrent imports", ^{
            [fileManager setContentsOfReportsDir:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];
            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:notNilValue() forArgument:1] willReturnUnsignedInteger:999];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            [verify(app) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.blue"]];

            assertWithTimeout(2.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [verifyCount(app, never()) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:999];

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verifyCount(app, times(1)) endBackgroundTask:999];
        });

        it(@"begins and ends only one background task for loading reports", ^{
            [fileManager setContentsOfReportsDir:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [[redType enqueueImport] block];
            TestImportProcess *blueImport = [blueType enqueueImport];
            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:notNilValue() forArgument:1] willReturnUnsignedInteger:999];

            [store loadReports];

            assertWithTimeout(1.0, thatEventually(@(blueImport.report.isEnabled)), isTrue());

            [verifyCount(app, times(1)) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [[verifyCount(app, never()) withMatcher:anything()] endBackgroundTask:999];

            [redImport unblock];

            assertWithTimeout(1.0, thatEventually(@(redImport.report.isEnabled)), isTrue());

            [verifyCount(app, never()) beginBackgroundTaskWithName:notNilValue() expirationHandler:notNilValue()];
            [verifyCount(app, times(1)) endBackgroundTask:999];
        });
        
        it(@"saves the import state and stops the background task when the OS calls the expiration handler", ^{

            // TODO: verify the archive extract points get saved when that's implemented

            [fileManager setContentsOfReportsDir:@"test.red", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            NSOperation *step = [[NSBlockOperation blockOperationWithBlock:^{}] block];
            redImport.steps = @[step];
            HCArgumentCaptor *expirationBlockCaptor = [[HCArgumentCaptor alloc] init];
            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:expirationBlockCaptor forArgument:1] willReturnUnsignedInteger:999];

            [store attemptToImportReportFromResource:[reportsDir URLByAppendingPathComponent:@"test.red"]];

            assertWithTimeout(1.0, thatEventually(@(redImport.steps.firstObject.isExecuting)), isTrue());

            void (^expirationBlock)() = expirationBlockCaptor.value;
            expirationBlock();

            [redImport.steps.firstObject unblock];

            assertWithTimeout(1.0, thatEventually(@(!step.isExecuting && step.isCancelled)), isTrue());

            [verify(app) endBackgroundTask:999];
        });

        it(@"ends the background task when the last import fails", ^{

            [fileManager setContentsOfReportsDir:@"test.red", @"test.blue", nil];
            TestImportProcess *redImport = [redType enqueueImport];
            TestImportProcess *blueImport = [blueType enqueueImport];
            blueImport.steps = @[[[NSBlockOperation blockOperationWithBlock:^{}] block]];

            [[[given([app beginBackgroundTaskWithName:@"" expirationHandler:^{}]) withMatcher:notNilValue() forArgument:0] withMatcher:anything() forArgument:1] willDo:^id(NSInvocation *invoc) {
                return @999;
            }];

            [[givenVoid([app endBackgroundTask:0]) withMatcher:anything()] willDo:^id(NSInvocation *invoc) {
                NSNumber *taskIdArg = invoc.mkt_arguments[0];
                if (taskIdArg.unsignedIntegerValue != 999) {
                    failure(@"ended wrong task id");
                }
                return nil;
            }];

            NSNotificationCenter *notifications = store.notifications;
            __block Report *finishedReport;
            NotificationRecordingObserver *observer = [NotificationRecordingObserver
                observe:[ReportNotification reportImportFinished] on:notifications from:store withBlock:^(NSNotification *notification) {
                    finishedReport = notification.userInfo[@"report"];
                }];

            [store loadReports];

            assertWithTimeout(1.0, thatEventually(blueImport.report), notNilValue());
            assertWithTimeout(1.0, thatEventually(redImport.report), notNilValue());
            assertWithTimeout(1.0, thatEventually(finishedReport), sameInstance(redImport.report));

            [blueImport cancel];
            [blueImport.steps.firstObject unblock];

            assertWithTimeout(1.0, thatEventually(@(finishedReport == blueImport.report)), isTrue());

            expect(observer.received.count).to.equal(2);
            [verify(app) endBackgroundTask:999];

            [notifications removeObserver:observer];
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
