//
//  DICEDownloadManager.m
//  DICE
//
//  Created by Robert St. John on 11/3/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "DICEDownloadManager.h"


@implementation DICEDownload

- (instancetype)initWithUrl:(NSURL *)url
{
    self = [super init];

    _url = url;

    return self;
}

- (NSInteger)percentComplete
{
    if (self.bytesExpected <= 0) {
        return -1;
    }
    return (NSInteger) ((double)self.bytesReceived / (double)self.bytesExpected * 100.0);
}

@end


@implementation DICEDownloadManager {
    NSFileManager *_fileManager;
    NSMutableDictionary<NSNumber *, DICEDownload *> *_downloads;
    void (^_sessionCompletionHandler)();
}

- (instancetype)initWithDownloadDir:(NSURL *)downloadDir fileManager:(NSFileManager *)fileManager delegate:(id<DICEDownloadDelegate>)delegate
{
    self = [super init];

    _fileManager = fileManager;
    if (!_fileManager) {
        _fileManager = NSFileManager.defaultManager;
    }
    _downloadDir = downloadDir;
    if (_downloadDir == nil) {
        _downloadDir = [_fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:NULL];
    }
    _delegate = delegate;
    _downloads = [NSMutableDictionary dictionary];

    return self;
}

- (instancetype)init
{
    return [self initWithDownloadDir:nil fileManager:nil delegate:nil];
}

- (BOOL)isFinishingBackgroundEvents
{
    return _sessionCompletionHandler && UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
}

- (void)downloadUrl:(NSURL *)url
{
    if ([self isDownloadingUrl:url]) {
        return;
    }
    NSURLSessionDownloadTask *downloadTask = [_downloadSession downloadTaskWithURL:url];
    [self downloadForTask:downloadTask];
    [downloadTask resume];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    dispatch_async(dispatch_get_main_queue(), ^{
        DICEDownload *download = [self downloadForTask:downloadTask];
        download.bytesExpected = totalBytesExpectedToWrite;
        download.bytesReceived = totalBytesWritten;
        if (self.delegate) {
            [self.delegate downloadManager:self didReceiveDataForDownload:download];
        }
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    // TODO: anything?
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    DICEDownload *download = [self downloadForTask:downloadTask];
    NSURL *destFile = [self.downloadDir URLByAppendingPathComponent:download.fileName];
    if (self.delegate) {
        __block NSURL *overrideFile;
        dispatch_sync(dispatch_get_main_queue(), ^{
            overrideFile = [self.delegate downloadManager:self willFinishDownload:download movingToFile:destFile];
        });
        if (overrideFile) {
            destFile = overrideFile;
        }
    }
    [_fileManager moveItemAtURL:location toURL:destFile error:NULL];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_downloads removeObjectForKey:@(downloadTask.taskIdentifier)];
        download.downloadedFile = destFile;
        download.wasSuccessful = YES;
        if (self.delegate) {
            [self.delegate downloadManager:self didFinishDownload:download];
        }
    });
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes
{
    // TODO: resuming
}

- (DICEDownload *)downloadForTask:(NSURLSessionDownloadTask *)task
{
    __block DICEDownload *download;
    if (!NSThread.isMainThread) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            download = [self downloadForTask:task];
        });
        return download;
    }
    download = _downloads[@(task.taskIdentifier)];
    if (download == nil) {
        download = _downloads[@(task.taskIdentifier)] = [[DICEDownload alloc] initWithUrl:task.originalRequest.URL];
    }
    download.bytesExpected = task.countOfBytesExpectedToReceive;
    download.bytesReceived = task.countOfBytesReceived;
    if (task.response) {
        download.mimeType = task.response.MIMEType;
        download.fileName = task.response.suggestedFilename;
        download.httpResponseCode = ((NSHTTPURLResponse *)task.response).statusCode;
        download.httpResponseMessage = [NSHTTPURLResponse localizedStringForStatusCode:download.httpResponseCode];
    }
    return download;
}

- (BOOL)isDownloadingUrl:(NSURL *)url
{
    for (DICEDownload *download in _downloads.allValues) {
        if ([url isEqual:download.url]) {
            return YES;
        }
    }
    return NO;
}

- (void)handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)())completionHandler
{
    if ([identifier isEqualToString:_downloadSession.configuration.identifier]) {
        _sessionCompletionHandler = completionHandler;
    }
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
    if (_sessionCompletionHandler) {
        void (^handler)() = _sessionCompletionHandler;
        _sessionCompletionHandler = nil;
        dispatch_async(dispatch_get_main_queue(), handler);
    }
}

- (void)shutdown
{
    [_downloadSession finishTasksAndInvalidate];
}

@end
