//
//  NSFileManager+Convenience.h
//  DICE
//
//  Created by Robert St. John on 6/26/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSFileManager (Convenience)

- (BOOL)isDirectoryAtUrl:(NSURL *)url;
- (BOOL)isRegularFileAtUrl:(NSURL *)url;

@end
