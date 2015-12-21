//
//  BaseImportProcess.h
//  DICE
//
//  Created by Robert St. John on 7/23/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ImportProcess.h"

/**
 This is an abstract class that takes care of setting up the key-value observing on the
 NSOperation instances the subclass creates to notify the subclass that the operations
 will finish.  Therefore, subclasses overriding -observeValueForKeyPath:ofObject:change:context:
 should call the superclass implementation in order for the -stepWillFinish: message to
 be sent and consumed by the subclass, which is reason for this class's existance.
 */
@interface BaseImportProcess : NSObject <ImportProcess>

@property (readonly) Report *report;
@property (weak) id<ImportDelegate> delegate;

- (instancetype)initWithReport:(Report *)report NS_DESIGNATED_INITIALIZER;

- (NSOperation *)nextStep;

/**
 *  Subclasses should override/implement this method to create the NSOperation instances
 *  that will complete the import of the report for this BaseImportProcess.
 *  BaseImportProcess will listen for KVO notifications on the returned NSOperation
 *  instances in order to call the subclass implementation of -stepWillFinish:.  It
 *  is therefor important that the subclass override this method and not -nextStep:.
 *
 *  @return the next NSOperation step
 */
- (NSOperation *)createNextStep; //After:(NSArray *)steps

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
 */
- (void)stepWillFinish:(NSOperation *)step;

@end
