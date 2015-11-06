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
@property (weak) id<ImportDelegate> delegate;

- (instancetype)initWithReport:(Report *)report steps:(NSArray *)steps NS_DESIGNATED_INITIALIZER;

/**
 Subclasses can override this method perform housekeeping between steps, such as 
 passing the result of the given finishing operation to pending operations, sending 
 progress notifications, etc.  This will be called after the given operation's 
 main method has finished, but before its finished property becomes YES (at 
 least in the out-of-box NSOperation implementation), so this method will execute
 before any dependent operations can move to the ready state.  This is achieved
 by using a KVO observer on the operation object's isFinished key path in 
 conjunction with the NSKeyValueObservingOptionPrior KVO observing option.  It is 
 the responsibility of the overriding implementation to ensure that the given
 NSOperation argument is in fact an operation this BaseImportProcess owns.
 
 @param step the NSOperation step that will finish
 @param stepIndex the index of the finishing step in the self.steps array
 */
- (void)stepWillFinish:(NSOperation *)step stepIndex:(NSUInteger)stepIndex;

@end
