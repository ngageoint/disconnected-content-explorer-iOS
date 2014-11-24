//
//  FileTypes.h
//  InteractiveReports
//
//  Created by Robert St. John on 11/20/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol ResourceHandler <NSObject>

- (void)handleResource:(NSURL *)resource;

@end


@interface ResourceTypes : NSObject

+ (BOOL)canOpenResource:(NSURL *)resource;
+ (UIViewController<ResourceHandler> *)viewerForResource:(NSURL *)resource;

@end
