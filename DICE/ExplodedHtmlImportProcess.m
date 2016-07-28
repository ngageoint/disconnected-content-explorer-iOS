//
// Created by Robert St. John on 7/28/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "ExplodedHtmlImportProcess.h"


@implementation ExplodedHtmlImportProcess {

}

- (instancetype)initWithReport:(Report *)report fileManager:(NSFileManager *)fileManager
{
    if (!(self = [super initWithReport:report])) {
        return nil;
    }

    return self;
}

@end