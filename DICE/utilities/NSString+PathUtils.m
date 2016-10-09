//
//  NSString+PathUtils.m
//  DICE
//
//  Created by Robert St. John on 10/7/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "NSString+PathUtils.h"

@implementation NSString (PathUtils)

- (NSString *)pathRelativeToPath:(NSString *)parent
{
    NSArray *parentParts = parent.pathComponents;
    NSArray *pathParts = self.pathComponents;
    if (pathParts.count < parentParts.count) {
        return nil;
    }
    NSArray *pathParentParts = [pathParts subarrayWithRange:NSMakeRange(0, parentParts.count)];
    if (![pathParentParts isEqualToArray:parentParts]) {
        return nil;
    }
    NSArray *pathRelativeParts = [pathParts subarrayWithRange:NSMakeRange(parentParts.count, pathParts.count - parentParts.count)];
    return [pathRelativeParts componentsJoinedByString:@"/"];
}

@end
