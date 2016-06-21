//
//  ImportProcess+Internal.h
//  DICE
//
//  Created by Robert St. John on 5/19/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#ifndef ImportProcess_Internal_h
#define ImportProcess_Internal_h


#import "ImportProcess.h"


@interface ImportProcess ()

@property (readwrite, nonatomic) NSArray<NSOperation *> *steps;

- (void)stepWillFinish:(NSOperation *)step;
- (void)stepWillCancel:(NSOperation *)step;
- (void)cancelStepsAfterStep:(NSOperation *)step;

@end


#endif /* ImportProcess_Internal_h */
