//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "HtmlReportType.h"

#import "UnzipOperation.h"


@interface HtmlReportType()

@property (strong, nonatomic, readonly) NSFileManager *fileManager;
@property (strong, nonatomic, readonly) NSOperationQueue *workQueue;

@end


@implementation HtmlReportType

- (HtmlReportType *)initWithFileManager:(NSFileManager *)fileManager workQueue:(NSOperationQueue *)workQueue
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _fileManager = fileManager;
    _workQueue = workQueue;
    
    return self;
}


- (BOOL)couldHandleFile:(NSString *)filePath
{
    NSDictionary *fileAttrs = [_fileManager attributesOfItemAtPath:filePath error:nil];
    NSString *fileType = fileAttrs[NSFileType];
    if ([NSFileTypeRegular isEqualToString:fileType]) {
        NSString *ext = [filePath.pathExtension lowercaseString];
        return
            [@"zip" isEqualToString:ext] ||
            [@"html" isEqualToString:ext];
    }
    else if ([NSFileTypeDirectory isEqualToString:fileType]) {
        NSString *indexPath = [filePath stringByAppendingPathComponent:@"index.html"];
        BOOL indexPathIsDirectory = YES;
        BOOL exists = [_fileManager fileExistsAtPath:indexPath isDirectory:&indexPathIsDirectory];
        if (!exists) {
            return NO;
        }
        if (!indexPathIsDirectory) {
            return YES;
        }
    }
    NSLog(@"could support %@", filePath);
    return NO;
}


- (void)importReport:(Report *)report
{
    [UnzipOperation unzipFile:report.url toDir:nil onQueue:self.workQueue];
}

@end
