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

        [verify(mockDelegate) downloadManager:downloadManager willFinishDownload:captureDownload.value movingToFile:destUrl];
        [verify(mockDelegate) downloadManager:downloadManager didFinishDownload:captureDownload.value];
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
    });

    xit(@"handles duplicate downloaded file names", ^{
        failure(@"do it");
    });

    it(@"does not start a new download for a url already downloading", ^{
        NSURL *url = [NSURL URLWithString:@"http://dice.com/test-data"];
        NSURL *urlDup = [url copy];

        NSURLSessionDownloadTask *task1 = mock(NSURLSessionDownloadTask.class);
        [given([task1 taskIdentifier]) willReturnUnsignedInteger:123];
        [given([task1 countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task1 countOfBytesReceived]) willReturnLong:9999999];

        NSURLSessionDownloadTask *task2 = mock(NSURLSessionDownloadTask.class);
        [given([task2 taskIdentifier]) willReturnUnsignedInteger:246];
        [given([task2 countOfBytesExpectedToReceive]) willReturnLong:9999999];
        [given([task2 countOfBytesReceived]) willReturnLong:9999999];

        [[given([mockSession downloadTaskWithURL:anything()]) willReturn:task1] willReturn:task2];

        [downloadManager downloadUrl:url];
        [downloadManager downloadUrl:urlDup];

        [verifyCount(mockSession, times(1)) downloadTaskWithURL:equalTo(url)];
    });

    it(@"can start a new download for a url already downloaded", ^{
        failure(@"do it");
    });

    it(@"notifies the delegate about download progress", ^{
        failure(@"do it");
    });

});

SpecEnd
