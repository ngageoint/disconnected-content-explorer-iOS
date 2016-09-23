//
//  TestOperationQueue.h
//  DICE
//
//  Created by Robert St. John on 9/22/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TestOperationQueue : NSOperationQueue

@property (copy) void (^onAddOperation)(NSOperation *op);

@end
