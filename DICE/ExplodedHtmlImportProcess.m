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
        NSURL *indexUrl = [self.report.url URLByAppendingPathComponent:@"index.html"];
        [report performSelectorOnMainThread:@selector(setUrl:) withObject:indexUrl waitUntilDone:YES];
        [self.delegate reportWasUpdatedByImportProcess:self];
    }];

    self.steps = @[setIndexUrl];

    return self;
}

@end
