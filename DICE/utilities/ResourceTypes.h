//
//  FileTypes.h
//  InteractiveReports
//
//  Created by Robert St. John on 11/20/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "Report.h"


@protocol ResourceHandler <NSObject>

- (void)handleResource:(NSURL *)resource forReport:(Report *)report;

@end

@class UIViewController;

@interface ResourceTypes : NSObject

+ (NSArray *)supportedFileExtensions;
+ (BOOL)canOpenResource:(NSURL *)resource;
+ (UIViewController<ResourceHandler> *)viewerForResource:(NSURL *)resource;

@end
