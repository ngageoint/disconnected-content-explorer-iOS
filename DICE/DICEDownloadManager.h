//
//  DICEDownloadManager.h
//  DICE
//
//  Created by Robert St. John on 11/3/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface DICEDownload : NSObject

@property (readonly, nonnull) NSURL *url;
@property (nullable) NSString *fileName;
@property (nullable) NSString *mimeType;
@property int64_t bytesExpected;
@property int64_t bytesReceived;
@property (readonly) NSInteger percentComplete;
@property NSInteger httpResponseCode;
@property (nullable) NSString *httpResponseMessage;
@property BOOL wasSuccessful;
@property (nullable) NSURL *downloadedFile;

- (nullable instancetype)initWithUrl:(nonnull NSURL *)url;

@end


@protocol DICEDownloadDelegate;


@interface DICEDownloadManager : NSObject <NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDownloadDelegate>

//@property (class, nonnull, nonatomic) DICEDownloadManager *sharedInstance;

@property (nullable) NSURLSession *downloadSession;
/** the URL of the directory where this download manager will move downloaded files */
@property (readonly, nonnull) NSURL *downloadDir;
@property (readonly, nullable, weak) id<DICEDownloadDelegate> delegate;

- (instancetype)initWithDownloadDir:(NSURL *)downloadDir fileManager:(NSFileManager *)fileManager delegate:(id<DICEDownloadDelegate>)delegate;

- (void)downloadUrl:(nonnull NSURL *)url;
- (void)handleEventsForBackgroundURLSession:(nonnull NSString *)identifier completionHandler:(nullable void (^)())completionHandler;

@end


/**
 * All delegate methods run on the main thread.  All except downloadManager:willFinishDownload:movingToFile:
 * are dispatched asynchronously.  Therefore, that method should return quickly to avoid blocking the progress
 * of the download manager.  Further, one must not call dispatch_sync(dispatch_get_main_queue(), ...) from that
 * method.
 */
@protocol DICEDownloadDelegate <NSObject>

/**
 * Indicate the download manager has received data for the given download.  The download manager updates
 * the given download's bytesExpected and bytesReceived properties appropriately.  The download manager
 * invokes this method asynchronously on the main thread.
 * @param downloadManager
 * @param download
 *
 * TODO: the download object's bytesReceived might get updated again when more data is received before
 * the delegate processes the value.  include a bytesReceived argument as well as updating the download
 * object's bytesReceived so it doesn't change on the download object before the delegate consumes it?
 * does it matter?  the download manager updates the download object on the main thread and calls the
 * delegate serially, so the delegate can capture the value safely if necessary.
 */
- (void)downloadManager:(nonnull DICEDownloadManager *)downloadManager didReceiveDataForDownload:(nonnull DICEDownload *)download;
/**
 * Indicate the download manager has finished downloading the file and will move the temporary file to
 * the given permanent destination.  The delegate can override the permanent destination by returning
 * a non-nil NSURL object referencing the desired final destination.  The download manager invokes this
 * method synchronously on the main thread.
 */
- (nullable NSURL *)downloadManager:(nonnull DICEDownloadManager *)downloadManager willFinishDownload:(nonnull DICEDownload *)download movingToFile:(nonnull NSURL *)destFile;
/**
 * Indicate the download manager has finished downloading the file and moved the file to its permanent
 * location, which the download manager conveys via the given download object's downloadedFile property.
 * The download manager invokes this method asynchronously on the main thread.
 * @param downloadManager
 * @param download
 */
- (void)downloadManager:(nonnull DICEDownloadManager *)downloadManager didFinishDownload:(nonnull DICEDownload *)download;

@end
