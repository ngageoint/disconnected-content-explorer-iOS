//
//  Report.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import "ReportCache.h"


typedef NS_ENUM(int16_t, ReportImportStatus) {
    ReportImportStatusNew,
    ReportImportStatusNewRemote,
    ReportImportStatusDownloading,
    ReportImportStatusNewLocal,
    ReportImportStatusExtracting,
    ReportImportStatusImporting,
    ReportImportStatusSuccess,
    ReportImportStatusFailed,
    ReportImportStatusDeleting,
    ReportImportStatusDeleted
};


@interface Report : NSManagedObject

// TODO: add ReportType reference to materialize more easily after initial import?
// @property NSString *reportTypeKey; // or something

@property (readonly, nonatomic) NSUInteger downloadPercent;

@property (readonly) BOOL isImportFinished;
@property (readonly, nullable) NSURL *thumbnail;
@property (readonly, nullable) NSURL *tileThumbnail;

@property (nonnull) NSMutableArray<ReportCache *> * cacheFiles;

/**
 Set the properties of this report from key-value pairs in the given
 JSON descriptor dictionary.

 @return self
 */
- (nonnull instancetype)setPropertiesFromJsonDescriptor:(nullable NSDictionary *)descriptor;

@end

#import "Report+CoreDataProperties.h"
