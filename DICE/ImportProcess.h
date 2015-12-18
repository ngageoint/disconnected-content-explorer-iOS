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
 An array of NSOperation objects that perform the work of importing
 the report
 */
@property (readonly) NSArray *steps;

/**
 TODO: document
 */
@property (weak) id<ImportDelegate> delegate;

@end



@protocol ImportDelegate <NSObject>

@optional

- (void)reportWasUpdatedByImportProcess:(id<ImportProcess>)import;
- (void)importDidFinishForImportProcess:(id<ImportProcess>)import;

// TODO:
//- (void)importDidSucceedForImportProcess:(id<ImportProcess>)import;
//- (void)importDidFailForImportProcess:(id<ImportProcess>)import;

@end