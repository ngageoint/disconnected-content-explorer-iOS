//
//  ImportOperation.h
//  DICE
//
//  Created by Robert St. John on 6/7/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@protocol ImportDelegate;
@class Report;


@interface ImportProcess : NSObject

@property (readonly, nonnull) Report *report;
@property (readonly, nonnull) NSArray<NSOperation *> *steps;
@property (weak, nullable) id<ImportDelegate> delegate;

- (nullable instancetype)initWithReport:(nonnull Report *)report NS_DESIGNATED_INITIALIZER;

@end



@protocol ImportDelegate <NSObject>

- (void)reportWasUpdatedByImportProcess:(nonnull ImportProcess *)import;
- (void)importDidFinishForImportProcess:(nonnull ImportProcess *)import;

// TODO:
//- (void)importDidSucceedForImportProcess:(id<ImportProcess>)import;
//- (void)importDidFailForImportProcess:(id<ImportProcess>)import;

@end