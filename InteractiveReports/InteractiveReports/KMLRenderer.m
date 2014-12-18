//
//  KMLRenderer.m
//  InteractiveReports
//
//  Created by Robert St. John on 12/17/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "KMLRenderer.h"

#import "SimpleKML.h"


@interface KMLRenderer ()

@property (strong, nonatomic) NSURL *kmlFile;
@property (strong, nonatomic) SimpleKML *kml;

@end


@implementation KMLRenderer

- (id)initWithKMLFile:(NSURL *)kmlFile
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    self.kmlFile = kmlFile;
    [self parseKML];
    
    return self;
}

- (void)parseKML
{
    NSError *parseError;
    self.kml = [SimpleKML KMLWithContentsOfURL:self.kmlFile error:&parseError];
}


@end
