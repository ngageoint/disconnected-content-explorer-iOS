
#ifndef DICE_ReportType_h
#define DICE_ReportType_h


#import "Report.h"


@protocol ReportType <NSObject>

- (BOOL)couldHandleFile:(NSURL *)reportPath;
- (void)importReport:(Report *)report;

@end


#endif
