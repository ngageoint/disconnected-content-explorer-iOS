//
//  ImportOperation.h
//  DICE
//
//  Created by Robert St. John on 6/7/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Report.h"


@protocol ImportDelegate;


@protocol ImportProcess <NSObject>

/**
 TODO: document
 */
@property (readonly) Report *report;
/**
 TODO: document
 */
@property (readonly) NSArray *steps;
/**
 TODO: document
 */
@property id<ImportDelegate> delegate;

@end


@protocol ImportDelegate <NSObject>

- (void)import:(id<ImportProcess>)import didFinishStep:(NSOperation *)step;

@end