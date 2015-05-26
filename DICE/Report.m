//
//  Report.m
//  InteractiveReports
//

#import "Report.h"

@implementation Report

- (id) initWithTitle:(NSString *)title {
    self = [super init];

    if (self) {
        self.title = title;
        self.summary = nil;
        self.thumbnail = nil;
        self.fileExtension = nil;
        self.reportID = nil;
        self.isEnabled = NO;
        self.error = nil;
        self.totalNumberOfFiles = 0;
        self.progress = 0;
    }
    
    return self;
}

- (NSURL *) thumbnailURL {
    return [NSURL URLWithString:self.thumbnail];
}

@end
