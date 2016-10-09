//
//  NSString+PathUtils.h
//  DICE
//
//  Created by Robert St. John on 10/7/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (PathUtils)

/**
 * Return the portion of the path represented by this string that is relative
 * to the given parent path.  If the path represented by this string is not
 * a child of the given parent path, return nil.
 */
- (NSString *)pathRelativeToPath:(NSString *)parent;

@end
