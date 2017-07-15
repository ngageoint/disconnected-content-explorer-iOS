//
// Created by Robert St. John on 7/28/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "ExplodedHtmlImportProcess.h"
#import "ImportProcess+Internal.h"
#import "ParseJsonOperation.h"


@implementation ExplodedHtmlImportProcess {

}

- (instancetype)initWithReport:(Report *)report
{
    if (!(self = [super initWithReport:report])) {
        return nil;
    }

    NSBlockOperation *setIndexUrl = [NSBlockOperation blockOperationWithBlock:^{
        [report.managedObjectContext performBlockAndWait:^{
            report.rootFilePath = @"index.html";
            [self.delegate reportWasUpdatedByImportProcess:self];
        }];
    }];

    self.steps = @[setIndexUrl];

    return self;
}

@end
