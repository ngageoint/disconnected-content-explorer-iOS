
#ifndef DICE_ReportType_h
#define DICE_ReportType_h


#import "Report.h"

#import "ImportProcess.h"


@protocol ReportType <NSObject>

- (BOOL)couldHandleFile:(NSURL *)reportPath;
- (nullable ImportProcess *)createProcessToImportReport:(Report *)report toDir:(NSURL *)destDir;

@end


#endif
