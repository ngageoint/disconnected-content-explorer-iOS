//
//  NSURL+ResourceValues.m
//  DICE
//
//  Created by Robert St. John on 6/16/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "NSURL+ResourceValues.h"

@implementation NSURL (ResourceValues)


- (NSNumber *)isDirectory
{
    NSString *value;
    NSError *err;
    if (![self getResourceValue:&value forKey:NSURLFileResourceTypeKey error:&err] && err) {
        NSLog(@"error getting NSURLFileResourceTypeKey: %@", err);
        return nil;
    }
    return [NSNumber numberWithBool:[NSURLFileResourceTypeDirectory isEqualToString:value]];
}

- (NSString *)typeIdentifier
{
    NSString *value;
    NSError *err;
    if (![self getResourceValue:&value forKey:NSURLTypeIdentifierKey error:&err] && err) {
        NSLog(@"error getting NSURLTypeIdentifierKey: %@", err);
        return nil;
    }
    return value;
}

@end
