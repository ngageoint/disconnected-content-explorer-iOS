//
//  ReportCache.m
//  DICE
//
//  Created by Brian Osborn on 3/11/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "ReportCache.h"

@implementation ReportCache

- (id) initWithName:(NSString *)name andPath: (NSString *) path andShared: (BOOL) shared{
    self = [super init];
    
    if (self) {
        self.name = name;
        self.path = path;
        self.shared = shared;
    }
    
    return self;
}

@end
