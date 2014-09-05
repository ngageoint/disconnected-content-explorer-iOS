//
//  ReportManager.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "zlib.h"
#import "ZipFile.h"
#import "ZipReadStream.h"
#import "ZipException.h"
#import "FileInZipInfo.h"
#import "Report.h"

@interface LocalReportManager : NSObject

- (NSMutableArray*)getReports;
- (void)loadReports;

@end
