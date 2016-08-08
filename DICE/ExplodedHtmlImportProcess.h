//
// Created by Robert St. John on 7/28/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ImportProcess.h"


@interface ExplodedHtmlImportProcess : ImportProcess

- (instancetype)initWithReport:(Report *)report fileManager:(NSFileManager *)fileManager;

@end