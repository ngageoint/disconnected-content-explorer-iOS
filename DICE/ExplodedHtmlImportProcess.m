//
// Created by Robert St. John on 7/28/16.
// Copyright (c) 2016 mil.nga. All rights reserved.
//

#import "ExplodedHtmlImportProcess.h"
#import "ImportProcess+Internal.h"
#import "ParseJsonOperation.h"


@implementation ExplodedHtmlImportProcess {

}

- (instancetype)initWithReport:(Report *)report fileManager:(NSFileManager *)fileManager
{
    if (!(self = [super initWithReport:report])) {
        return nil;
    }

    ParseJsonOperation *parseDescriptor = [[ParseJsonOperation alloc] initWithFileManager:fileManager];
    NSString *descriptorPath = [report.url.path stringByAppendingPathComponent:@"metadata.json"];
    parseDescriptor.jsonUrl = [NSURL fileURLWithPath:descriptorPath isDirectory:NO];
    self.steps = @[parseDescriptor];

    return self;
}

- (void)stepWillFinish:(NSOperation *)step
{
    dispatch_async(dispatch_get_main_queue(), ^{
        ParseJsonOperation *parseDescriptor = (ParseJsonOperation *) self.steps.firstObject;
        if (parseDescriptor.parsedJsonDictionary) {
            [self.report setPropertiesFromJsonDescriptor:parseDescriptor.parsedJsonDictionary];
        }
        if (self.delegate) {
            [self.delegate importDidFinishForImportProcess:self];
        }
    });
}

@end