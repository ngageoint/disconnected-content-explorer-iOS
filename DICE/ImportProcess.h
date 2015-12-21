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
@property (weak) id<ImportDelegate> delegate;

/**
 *  Return the next step in the import process.  The ImportProcess
 *  should retain references to the NSOperation steps it creates
 *  as necessary, either explicitly or implicitly through key-value
 *  observation, block closure, etc.  Additionally, the caller may
 *  begin executing the NSOperation instances before calling this
 *  method enough to create all the steps.
 *
 *  @return the next NSOperation in the import process or nil when
 *      there are no more steps
 */
- (NSOperation *)nextStep;

@end



@protocol ImportDelegate <NSObject>

@optional

- (void)reportWasUpdatedByImportProcess:(id<ImportProcess>)import;
- (void)importDidFinishForImportProcess:(id<ImportProcess>)import;

// TODO:
//- (void)importDidSucceedForImportProcess:(id<ImportProcess>)import;
//- (void)importDidFailForImportProcess:(id<ImportProcess>)import;

@end