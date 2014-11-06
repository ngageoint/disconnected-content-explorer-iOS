//
//  Report.m
//  InteractiveReports
//

#import "Report.h"

@implementation Report

@synthesize description; // really weird, had to add this after the switch to XCode 6

- (id) initWithTitle:(NSString *)title {
    self = [super init];
    
    if ( self ){
        self.title = title;
        self.description = nil;
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

+ (id) reportWithTitle:(NSString *)title {
    return [[self alloc] initWithTitle:title];
}

- (NSURL *) thumbnailURL {
    return [NSURL URLWithString:self.thumbnail];
}

@end
