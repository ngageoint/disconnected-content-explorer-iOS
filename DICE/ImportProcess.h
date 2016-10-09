//
//  ImportProcess.h
//  DICE
//
//  Created by Robert St. John on 6/7/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol ImportDelegate;
@class Report;


@interface ImportProcess : NSObject

@property (readonly, nonatomic, nonnull) Report *report;
@property (readonly, nonatomic, nonnull) NSArray<NSOperation *> *steps;
/**
 * This property will be YES only after the isFinished property of every
 * step is YES and after this process calls the delegate's importDidFinishForImportProcess:
 * method.
 */
@property (readonly) BOOL isFinished;
/**
 * This property returns YES if all steps finished normally and were not cancelled.
 */
@property (readonly) BOOL wasSuccessful;
@property (weak, nonatomic, nullable) id<ImportDelegate> delegate;

- (nullable instancetype)initWithReport:(nonnull Report *)report NS_DESIGNATED_INITIALIZER;

/**
 * Cancel all the NSOperation steps for this ImportProcess.
 * Subclasses should override and call this method to perform any cleanup associated
 * with cancelling the import process, such as temporary files or saving state.
 */
- (void)cancel;

@end



@protocol ImportDelegate <NSObject>

- (void)reportWasUpdatedByImportProcess:(nonnull ImportProcess *)import;
- (void)importDidFinishForImportProcess:(nonnull ImportProcess *)import;

// TODO:
//- (void)importDidSucceedForImportProcess:(id<ImportProcess>)import;

@end
