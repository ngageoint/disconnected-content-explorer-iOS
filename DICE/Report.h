//
//  Report.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "ReportCache.h"


typedef NS_ENUM(NSUInteger, ReportImportStatus) {
    ReportImportStatusNewLocal,
    ReportImportStatusNewRemote,
    ReportImportStatusDownloading,
    ReportImportStatusExtracting,
    ReportImportStatusImporting,
    ReportImportStatusSuccess,
    ReportImportStatusFailed,
    ReportImportStatusDeleting,
    ReportImportStatusDeleted
};


@interface Report : NSObject

@property (nonatomic) NSString *reportID;
@property (nonatomic) NSString *title;
@property (nonatomic) NSString *summary;
@property (nonatomic) NSString *thumbnail;
@property (nonatomic) NSString *tileThumbnail;
/** the url of the resource that a client should load first when viewing this report */
@property (nonatomic) NSURL *rootResource;
/**
 * the url of the base directory for this report's content;
 * nil if the content is a single resource in the reports directory,
 * e.g., a PDF or MS Office file
 */
@property (nonatomic) NSURL *baseDir;
/** the uniform type identifier of the report's root resource */
@property (nonatomic) CFStringRef uti;
@property (nonatomic) NSNumber *lat;
@property (nonatomic) NSNumber *lon;
@property (nonatomic) NSUInteger downloadSize;
@property (nonatomic) NSUInteger downloadProgress;
@property (nonatomic) BOOL isEnabled;
@property (nonatomic) ReportImportStatus importStatus;
// TODO: use status message to display information instead of summary
@property (nonatomic) NSString *statusMessage;
/** convenience method that returns YES if the import status is success or failed */
@property (readonly, nonatomic) BOOL isImportFinished;
@property (nonatomic) NSMutableArray<ReportCache *> * cacheFiles;

- (instancetype)initWithTitle:(NSString *)title;

/**
 Set the properties of this report from key-value pairs in the given
 JSON descriptor dictionary.

 @return self
 */
- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor;

@end
