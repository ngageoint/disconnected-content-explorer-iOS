//
//  HtmlReport.m
//  DICE
//
//  Created by Robert St. John on 5/21/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "HtmlReportType.h"


@interface HtmlReportType()

@property (strong, nonatomic, readonly) NSFileManager *fileManager;

@end


@implementation HtmlReportType

- (HtmlReportType *)initWithFileManager:(NSFileManager *)fileManager
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _fileManager = fileManager;
    
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
            NSLog(@"%@ does not exist", indexPath);
            return NO;
        }
        if (indexPathIsDirectory) {
            NSLog(@"%@ is a directory", indexPath);
            return NO;
        }
    }
    NSLog(@"could support %@", filePath);
    return YES;
}





@end
