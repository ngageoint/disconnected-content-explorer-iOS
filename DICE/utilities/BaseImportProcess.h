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

@property (readonly) Report *report;
@property (readonly) NSArray *steps;
@property id<ImportDelegate> delegate;

- (instancetype)initWithReport:(Report *)report steps:(NSArray *)steps NS_DESIGNATED_INITIALIZER;

@end
