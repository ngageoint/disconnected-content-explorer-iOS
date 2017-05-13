//
//  TestFileManager.h
//  DICE
//
//  Created by Robert St. John on 5/13/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface TestFileManager : NSFileManager

@property NSURL *reportsDir;
@property NSMutableOrderedSet<NSString *> *pathsInReportsDir;
@property NSMutableDictionary *pathAttrs;
@property BOOL (^onCreateFileAtPath)(NSString *path);
@property BOOL (^onCreateDirectoryAtURL)(NSURL *path, BOOL createIntermediates, NSError **error);
@property NSMutableDictionary<NSString *, NSData *> *contentsAtPath;

- (void)setContentsOfReportsDir:(NSString *)relPath, ... NS_REQUIRES_NIL_TERMINATION;

@end
