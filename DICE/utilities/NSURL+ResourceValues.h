//
//  NSURL+ResourceValues.h
//  DICE
//
//  Created by Robert St. John on 6/16/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURL (ResourceValues)


/**
 * Return a wrapped boolean indicating whether self's value for the NSURLFileResourceTypeKey is NSURLFileResourceTypeDirectory.
 * Return nil if an error occurs retrieving the value.
 */
- (nullable NSNumber *)isDirectory;

/**
 * Return self's value for the NSURLTypeIdentifierKey, which is the uniform type identifier (UTI).
 * Return nil if the value is nil or an error occurs retrieving the value.
 */
- (nullable NSString *)typeIdentifier;

@end
