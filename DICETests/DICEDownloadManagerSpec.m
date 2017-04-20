//
//  DICEDownloadManagerSpec.m
//  DICE
//
//  Created by Robert St. John on 11/18/16.
//  Copyright 2016 mil.nga. All rights reserved.
//

#import "Specta.h"
#import <Expecta/Expecta.h>
#import <OCHamcrest/OCHamcrest.h>
#import <OCMockito/OCMockito.h>

#import "DICEDownloadManager.h"


SpecBegin(DICEDownloadManager)

describe(@"DICEDownloadManager", ^{

    __block NSURL *downloadDir;
    __block NSFileManager *mockFileManager;
    __block NSURLSession *mockSession;
    __block id<DICEDownloadDelegate> mockDelegate;
    __block DICEDownloadManager *downloadManager;
    __block NSOperationQueue *urlSessionQueue;

    beforeAll(^{

    });

    beforeEach(^{
        downloadDir = [NSURL fileURLWithPath:@"/dice/downloads" isDirectory:YES];
        mockFileManager = mock([NSFileManager class]);
        mockDelegate = mockProtocol(@protocol(DICEDownloadDelegate));
        downloadManager = [[DICEDownloadManager alloc] initWithDownloadDir:downloadDir fileManager:mockFileManager delegate:mockDelegate];
        mockSession = mock(NSURLSession.class);
        downloadManager.downloadSession = mockSession;
        urlSessionQueue = [[NSOperationQueue alloc] init];
    });

    afterEach(^{
        [urlSessionQueue waitUntilAllOperationsAreFinished];
    });

    afterAll(^{

    });

    it(@"notifies the delegate before and after moving the file when the download completes", ^{

        NSURL *tempUrl = [NSURL fileURLWithPath:@"/tmp/abc123" isDirectory:NO];
        NSURL *destUrl = [downloadDir URLByAppendingPathComponent:@"test.dat"];
        NSURLSessionDownloadTask *task = mock(NSURLSessionDownloadTask.class);
        [given([task taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task countOfBytesReceived]) willReturnLong:9999999];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:[NSURL URLWithString:@"http://dice.com/test-data"] statusCode:200 HTTPVersion:@"1.1"
            headerFields:@{@"Content-Disposition": @"attachment; filename=test.dat", @"Content-Type": @"application/test-data"}];
        [given([task response]) willReturn:response];
        [given([mockFileManager moveItemAtURL:tempUrl toURL:destUrl error:NULL]) willReturnBool:YES];
        HCArgumentCaptor *captureDownload = [[HCArgumentCaptor alloc] init];
        __block BOOL delegateWillFinish = NO;
        [given([mockDelegate downloadManager:downloadManager willFinishDownload:captureDownload movingToFile:anything()]) willDo:^id(NSInvocation *invocation) {
            delegateWillFinish = NSThread.isMainThread;
            return nil;
        }];
        __block BOOL delegateFinished = NO;
        [givenVoid([mockDelegate downloadManager:downloadManager didFinishDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            delegateFinished = NSThread.isMainThread;
            return nil;
        }];

        [urlSessionQueue addOperationWithBlock:^{
            [downloadManager URLSession:mockSession downloadTask:task didFinishDownloadingToURL:tempUrl];
            expect(delegateWillFinish).to.beTruthy();
            expect(delegateFinished).to.beFalsy();
        }];

        assertWithTimeout(1.0, thatEventually(@(delegateFinished)), isTrue());

        DICEDownload *download = captureDownload.value;
        expect(captureDownload).toNot.beNil();
        [verify(mockDelegate) downloadManager:downloadManager willFinishDownload:download movingToFile:destUrl];
        [verify(mockDelegate) downloadManager:downloadManager didFinishDownload:download];
    });

    it(@"moves the downloaded file serially on the invoking background thread", ^{

        NSURL *tempUrl = [NSURL fileURLWithPath:@"/tmp/abc123" isDirectory:NO];
        NSURL *destUrl = [downloadDir URLByAppendingPathComponent:@"test.dat"];
        NSURLSessionDownloadTask *task = mock(NSURLSessionDownloadTask.class);
        [given([task taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task countOfBytesReceived]) willReturnLong:9999999];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:[NSURL URLWithString:@"http://dice.com/test-data"] statusCode:200 HTTPVersion:@"1.1"
            headerFields:@{@"Content-Disposition": @"attachment; filename=test.dat", @"Content-Type": @"application/test-data"}];
        [given([task response]) willReturn:response];
        __block BOOL movedFile = NO;
        __block NSThread *downloadThread;
        [given([mockFileManager moveItemAtURL:tempUrl toURL:destUrl error:NULL]) willDo:^id(NSInvocation *invocation) {
            movedFile = NSThread.currentThread == downloadThread;
            return @YES;
        }];
        __block BOOL delegateFinished = NO;
        [givenVoid([mockDelegate downloadManager:downloadManager didFinishDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            delegateFinished = NSThread.isMainThread;
            return nil;
        }];

        [urlSessionQueue addOperationWithBlock:^{
            downloadThread = NSThread.currentThread;
            [downloadManager URLSession:mockSession downloadTask:task didFinishDownloadingToURL:tempUrl];
            expect(movedFile).to.beTruthy();
        }];

        assertWithTimeout(1.0, thatEventually(@(delegateFinished)), isTrue());

        downloadThread = nil;
    });

    it(@"moves the downloaded file to the download dir with the suggested file name", ^{

        NSURL *tempUrl = [NSURL fileURLWithPath:@"/tmp/abc123" isDirectory:NO];
        NSURL *destUrl = [downloadDir URLByAppendingPathComponent:@"test.dat"];
        NSURLSessionDownloadTask *task = mock(NSURLSessionDownloadTask.class);
        [given([task taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task countOfBytesReceived]) willReturnLong:9999999];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:[NSURL URLWithString:@"http://dice.com/test-data"] statusCode:200 HTTPVersion:@"1.1"
            headerFields:@{@"Content-Disposition": @"attachment; filename=test.dat", @"Content-Type": @"application/test-data"}];
        [given([task response]) willReturn:response];
        [given([mockFileManager moveItemAtURL:tempUrl toURL:destUrl error:NULL]) willReturnBool:YES];
        [given([mockDelegate downloadManager:downloadManager willFinishDownload:anything() movingToFile:anything()]) willReturn:nil];
        __block DICEDownload *download;
        [givenVoid([mockDelegate downloadManager:downloadManager didFinishDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            download = invocation.mkt_arguments[1];
            return nil;
        }];

        [urlSessionQueue addOperationWithBlock:^{
            [downloadManager URLSession:mockSession downloadTask:task didFinishDownloadingToURL:tempUrl];
        }];

        assertWithTimeout(1.0, thatEventually(download), notNilValue());

        [verify(mockFileManager) moveItemAtURL:tempUrl toURL:destUrl error:NULL];
        expect(response.suggestedFilename).to.equal(@"test.dat");
        expect(download.downloadedFile).to.equal(destUrl);
        expect(download.wasSuccessful).to.beTruthy();
    });

    it(@"moves the downloaded file to the override path", ^{

        NSURL *tempUrl = [NSURL fileURLWithPath:@"/tmp/abc123" isDirectory:NO];
        NSURL *destUrl = [downloadDir URLByAppendingPathComponent:@"override.dat"];
        NSURLSessionDownloadTask *task = mock(NSURLSessionDownloadTask.class);
        [given([task taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task countOfBytesReceived]) willReturnLong:9999999];
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:[NSURL URLWithString:@"http://dice.com/test-data"] statusCode:200 HTTPVersion:@"1.1"
            headerFields:@{@"Content-Disposition": @"attachment; filename=test.dat", @"Content-Type": @"application/test-data"}];
        [given([task response]) willReturn:response];
        [given([mockFileManager moveItemAtURL:tempUrl toURL:destUrl error:NULL]) willReturnBool:YES];
        [given([mockDelegate downloadManager:downloadManager willFinishDownload:anything() movingToFile:anything()]) willReturn:destUrl];
        __block DICEDownload *download;
        [givenVoid([mockDelegate downloadManager:downloadManager didFinishDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            download = invocation.mkt_arguments[1];
            return nil;
        }];

        [urlSessionQueue addOperationWithBlock:^{
            [downloadManager URLSession:mockSession downloadTask:task didFinishDownloadingToURL:tempUrl];
        }];

        assertWithTimeout(1.0, thatEventually(download), notNilValue());

        [verify(mockFileManager) moveItemAtURL:tempUrl toURL:destUrl error:NULL];
        expect(response.suggestedFilename).to.equal(@"test.dat");
        expect(download.downloadedFile).to.equal(destUrl);
        expect(download.wasSuccessful).to.beTruthy();
    });

    it(@"notifies the delegate when the response has an error code", ^{

        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:[NSURL URLWithString:@"http://dice.com/test-data"] statusCode:400 HTTPVersion:@"1.1"
            headerFields:@{@"Content-Disposition": @"attachment; filename=test.dat", @"Content-Type": @"application/test-data"}];

        NSURLSessionDownloadTask *task = mock(NSURLSessionDownloadTask.class);
        [given([task taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task countOfBytesExpectedToReceive]) willReturnLong:0];
        [given([task countOfBytesReceived]) willReturnLong:0];
        [given([task response]) willReturn:response];

        HCArgumentCaptor *captureDownload = [[HCArgumentCaptor alloc] init];

        __block BOOL delegateFinished = NO;
        [givenVoid([mockDelegate downloadManager:downloadManager didFinishDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            delegateFinished = YES;
            return nil;
        }];

        [urlSessionQueue addOperationWithBlock:^{
            [downloadManager URLSession:mockSession task:task didCompleteWithError:nil];
        }];

        assertWithTimeout(1.0, thatEventually(@(delegateFinished)), isTrue());

        [verify(mockDelegate) downloadManager:downloadManager didFinishDownload:captureDownload];

        DICEDownload *download = captureDownload.value;
        expect(download.wasSuccessful).to.beFalsy();
        expect(download.httpResponseCode).to.equal(400);
        expect(download.errorMessage).to.equal([NSString stringWithFormat:@"Server response: (400) %@", [NSHTTPURLResponse localizedStringForStatusCode:400]]);
    });

    it(@"notifies the delegate when a client error occurs", ^{

        NSURLSessionDownloadTask *task = mock(NSURLSessionDownloadTask.class);
        [given([task taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task countOfBytesExpectedToReceive]) willReturnLong:0];
        [given([task countOfBytesReceived]) willReturnLong:0];

        HCArgumentCaptor *captureDownload = [[HCArgumentCaptor alloc] init];

        __block BOOL delegateFinished = NO;
        [givenVoid([mockDelegate downloadManager:downloadManager didFinishDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            delegateFinished = YES;
            return nil;
        }];

        [urlSessionQueue addOperationWithBlock:^{
            NSError *error = [NSError errorWithDomain:@"NSURLSession" code:999 userInfo:@{NSLocalizedDescriptionKey: @"test error"}];
            [downloadManager URLSession:mockSession task:task didCompleteWithError:error];
        }];

        assertWithTimeout(1.0, thatEventually(@(delegateFinished)), isTrue());

        [verify(mockDelegate) downloadManager:downloadManager didFinishDownload:captureDownload];

        DICEDownload *download = captureDownload.value;
        expect(download.wasSuccessful).to.beFalsy();
        expect(download.httpResponseCode).to.equal(0);
        expect(download.errorMessage).to.equal(@"Local error: test error");
    });

    it(@"was not successful when moving the temp file fails", ^{
        failure(@"do it");
    });

    xit(@"handles duplicate downloaded file names", ^{
        failure(@"do it");
    });

    it(@"does not start a new download for a url already downloading", ^{

        NSURL *url = [NSURL URLWithString:@"http://dice.com/test-data"];
        NSURL *urlDup = [url copy];

        NSURLRequest *req = [[NSURLRequest alloc] initWithURL:url];
        NSURLRequest *reqDup = [[NSURLRequest alloc] initWithURL:urlDup];

        NSURLSessionDownloadTask *task1 = mock(NSURLSessionDownloadTask.class);
        [given([task1 taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task1 originalRequest]) willReturn:req];
        [given([task1 countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task1 countOfBytesReceived]) willReturnLong:9999999];

        NSURLSessionDownloadTask *task2 = mock(NSURLSessionDownloadTask.class);
        [given([task2 taskIdentifier]) willReturnUnsignedInteger:246];
        [given([task2 originalRequest]) willReturn:reqDup];
        [given([task2 countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task2 countOfBytesReceived]) willReturnLong:9999999];

        [[given([mockSession downloadTaskWithURL:anything()]) willReturn:task1] willReturn:task2];

        [downloadManager downloadUrl:url];
        [downloadManager downloadUrl:urlDup];

        [verifyCount(mockSession, times(1)) downloadTaskWithURL:equalTo(url)];
    });

    it(@"can start a new download for a url already downloaded", ^{

        NSURL *url = [NSURL URLWithString:@"http://dice.com/test-data"];
        NSURL *urlDup = [url copy];

        NSURLRequest *req = [[NSURLRequest alloc] initWithURL:url];
        NSURLRequest *reqDup = [[NSURLRequest alloc] initWithURL:urlDup];

        __block BOOL delegateFinished = NO;
        [givenVoid([mockDelegate downloadManager:downloadManager didFinishDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            delegateFinished = YES;
            return nil;
        }];

        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:[NSURL URLWithString:@"http://dice.com/test-data"] statusCode:200 HTTPVersion:@"1.1"
            headerFields:@{@"Content-Disposition": @"attachment; filename=test.dat", @"Content-Type": @"application/test-data"}];

        NSURLSessionDownloadTask *task1 = mock(NSURLSessionDownloadTask.class);
        [given([task1 taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task1 originalRequest]) willReturn:req];
        [given([task1 countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task1 countOfBytesReceived]) willReturnLong:9999999];
        [given([task1 response]) willReturn:response];

        NSURLSessionDownloadTask *task2 = mock(NSURLSessionDownloadTask.class);
        [given([task2 taskIdentifier]) willReturnUnsignedInteger:246];
        [given([task2 originalRequest]) willReturn:reqDup];
        [given([task2 countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task2 countOfBytesReceived]) willReturnLong:9999999];
        [given([task2 response]) willReturn:response];

        [[given([mockSession downloadTaskWithURL:anything()]) willReturn:task1] willReturn:task2];

        [downloadManager downloadUrl:url];
        [urlSessionQueue addOperationWithBlock:^{
            [downloadManager URLSession:mockSession downloadTask:task1 didFinishDownloadingToURL:[NSURL fileURLWithPath:@"/tmp/abc123"]];
        }];

        assertWithTimeout(1.0, thatEventually(@(delegateFinished)), isTrue());

        delegateFinished = NO;
        [downloadManager downloadUrl:urlDup];
        [urlSessionQueue addOperationWithBlock:^{
            [downloadManager URLSession:mockSession downloadTask:task2 didFinishDownloadingToURL:[NSURL fileURLWithPath:@"/tmp/efg456"]];
        }];

        assertWithTimeout(1.0, thatEventually(@(delegateFinished)), isTrue());

        [verifyCount(mockSession, times(2)) downloadTaskWithURL:equalTo(url)];
    });

    it(@"notifies the delegate about download progress", ^{

        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:[NSURL URLWithString:@"http://dice.com/test-data"] statusCode:200 HTTPVersion:@"1.1"
            headerFields:@{@"Content-Disposition": @"attachment; filename=test.dat", @"Content-Type": @"application/test-data"}];

        NSURLSessionDownloadTask *task = mock(NSURLSessionDownloadTask.class);
        [given([task taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task countOfBytesExpectedToReceive]) willReturnLong:100];
        [[[given([task countOfBytesReceived]) willReturnLong:25] willReturnLong:50] willReturnLong:75];
        [given([task response]) willReturn:response];

        NSMutableArray<NSNumber *> *progressUpdates = [NSMutableArray array];
        HCArgumentCaptor *captureDownload = [[HCArgumentCaptor alloc] init];
        [givenVoid([mockDelegate downloadManager:downloadManager didReceiveDataForDownload:captureDownload]) willDo:^id(NSInvocation *invocation) {
            DICEDownload *download = captureDownload.value;
            [progressUpdates addObject:@(download.bytesReceived)];
            return nil;
        }];

        __block BOOL delegateFinished = NO;
        [givenVoid([mockDelegate downloadManager:downloadManager didFinishDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            delegateFinished = YES;
            return nil;
        }];

        [urlSessionQueue addOperationWithBlock:^{
            [downloadManager URLSession:mockSession downloadTask:task didWriteData:25 totalBytesWritten:25 totalBytesExpectedToWrite:100];
            [downloadManager URLSession:mockSession downloadTask:task didWriteData:25 totalBytesWritten:50 totalBytesExpectedToWrite:100];
            [downloadManager URLSession:mockSession downloadTask:task didWriteData:25 totalBytesWritten:75 totalBytesExpectedToWrite:100];
            [downloadManager URLSession:mockSession downloadTask:task didFinishDownloadingToURL:[NSURL fileURLWithPath:@"/tmp/abc123"]];
        }];

        assertWithTimeout(1.0, thatEventually(@(delegateFinished)), isTrue());

        [verifyCount(mockDelegate, times(3)) downloadManager:downloadManager didReceiveDataForDownload:captureDownload.value];
        expect(progressUpdates.count).to.equal(3);
        expect(progressUpdates[0]).to.equal(25);
        expect(progressUpdates[1]).to.equal(50);
        expect(progressUpdates[2]).to.equal(75);
    });

    it(@"updates the download file name when the response is available", ^{

        NSURL *url = [NSURL URLWithString:@"http://dice.com/test-data"];

        NSURLSessionDownloadTask *task = mock(NSURLSessionDownloadTask.class);
        [given([task taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task countOfBytesReceived]) willReturnLong:1024];
        [given([mockSession downloadTaskWithURL:anything()]) willReturn:task];

        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc]
            initWithURL:url statusCode:200 HTTPVersion:@"1.1"
            headerFields:@{@"Content-Disposition": @"attachment; filename=test.dat", @"Content-Type": @"application/test-data"}];

        [downloadManager downloadUrl:url];

        [given([task response]) willReturn:response];

        __block DICEDownload *download;
        __block NSString *fileName;
        [givenVoid([mockDelegate downloadManager:downloadManager didReceiveDataForDownload:anything()]) willDo:^id(NSInvocation *invocation) {
            download = invocation.mkt_arguments[1];
            fileName = download.fileName;
            return nil;
        }];

        [urlSessionQueue addOperationWithBlock:^{
            [downloadManager URLSession:mockSession downloadTask:task didWriteData:1024 totalBytesWritten:1024 totalBytesExpectedToWrite:9999999];
        }];

        assertWithTimeout(1.0, thatEventually(fileName), notNilValue());

        expect(response.suggestedFilename).to.equal(@"test.dat");
        expect(fileName).to.equal(@"test.dat");
        expect(download.fileName).to.equal(@"test.dat");
    });

    it(@"handles background events for the url session", ^{

        __block BOOL handled = NO;
        void (^handler)() = ^{ handled = NSThread.isMainThread; };
        [downloadManager handleEventsForBackgroundURLSession:@"test.session" completionHandler:handler];
        [downloadManager URLSessionDidFinishEventsForBackgroundURLSession:mockSession];

        assertWithTimeout(1.0, thatEventually(@(handled)), isTrue());
    });

});

SpecEnd
