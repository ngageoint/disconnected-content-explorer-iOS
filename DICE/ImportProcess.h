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


@interface ImportProcess : NSObject

@property (readonly) Report *report;
@property (readonly, nonatomic) NSArray<NSOperation *> *steps;
@property (readonly) NSInteger currentStep;
@property (weak) id<ImportDelegate> delegate;

- (instancetype)initWithReport:(Report *)report NS_DESIGNATED_INITIALIZER;

@end



@protocol ImportDelegate <NSObject>

@optional

- (void)reportWasUpdatedByImportProcess:(ImportProcess *)import;
- (void)importDidFinishForImportProcess:(ImportProcess *)import;

// TODO:
//- (void)importDidSucceedForImportProcess:(id<ImportProcess>)import;
//- (void)importDidFailForImportProcess:(id<ImportProcess>)import;

@end