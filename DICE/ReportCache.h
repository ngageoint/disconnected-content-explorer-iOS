//
//  ReportCache.h
//  DICE
//
//  Created by Brian Osborn on 3/11/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ReportCache : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *path;
@property (nonatomic) BOOL shared;

- (id) initWithName:(NSString *)name andPath: (NSString *) path andShared: (BOOL) shared;

@end
