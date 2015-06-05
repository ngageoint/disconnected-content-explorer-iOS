//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "HtmlReportType.h"

#import "SimpleFileManager.h"
#import "UnzipOperation.h"


@interface HtmlReportType()

@property (strong, nonatomic, readonly) id<SimpleFileManager> fileManager;
@property (strong, nonatomic, readonly) NSOperationQueue *workQueue;

@end


@implementation HtmlReportType

- (HtmlReportType *)initWithFileManager:(id<SimpleFileManager>)fileManager workQueue:(NSOperationQueue *)workQueue
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _fileManager = fileManager;
    _workQueue = workQueue;
    
    return self;
}


- (BOOL)couldHandleFile:(NSURL *)filePath
{
    id<FileInfo> fileInfo = [_fileManager infoForPath:filePath];
    if (fileInfo.isRegularFile)
    {
        NSString *ext = [filePath.pathExtension lowercaseString];
        return
            [@"zip" isEqualToString:ext] ||
            [@"html" isEqualToString:ext];
    }
    else if (fileInfo.isDirectory)
    {
        NSURL *indexPath = [filePath URLByAppendingPathComponent:@"index.html"];
        fileInfo = [_fileManager infoForPath:indexPath];
        return fileInfo && fileInfo.isRegularFile;
    }

    return NO;
}


- (void)importReport:(Report *)report
{
    NSURL *tempDir = [_fileManager createTempDir];
    UnzipOperation *unzip = [[UnzipOperation alloc] initWithZipFile:report.url destDir:tempDir fileManager:_fileManager];
    [_workQueue addOperation:unzip];
}

@end
