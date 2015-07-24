//
//  BaseImportProcess.h
//  DICE
//
//  Created by Robert St. John on 7/23/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ImportProcess.h"

@interface BaseImportProcess : NSObject <ImportProcess>

@property (nonatomic, readonly) Report *report;
@property (nonatomic, readonly) NSMutableArray *steps;

- (instancetype)initWithReport:(Report *)report NS_DESIGNATED_INITIALIZER;

@end
