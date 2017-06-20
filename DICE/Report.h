//
//  Report.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "ReportCache.h"


typedef NS_ENUM(NSUInteger, ReportImportStatus) {
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


@interface Report : NSObject <NSCoding>

// TODO: add ReportType reference to materialize more easily after initial import?
// @property NSString *reportTypeKey; // or something

// provided by descriptor/content author
@property NSString *contentId;
@property NSString *title;
@property NSString *summary;
@property NSString *thumbnail;
@property NSString *tileThumbnail;
@property NSNumber *lat;
@property NSNumber *lon;

// provided by app during/after import
/** the url of the resource from which this report was downloaded, or nil */
@property NSURL *remoteSource;
/** the file url of the resource from which this report was first imported, i.e., the url passed to ReportStore:attemptToImportReportFromResource: */
@property NSURL *sourceFile;
/** a container directory ReportStore creates to wrap extra information with report package's content */
@property NSURL *importDir;
/**
 * the file url of the base directory for this report's content;
 * nil if the content is a stand-alone resource in the import directory,
 * e.g., a PDF or MS Office file
 */
@property NSURL *baseDir;
/** the file url of the resource that a client should load first when viewing this report */
@property NSURL *rootFile;
/** the uniform type identifier of the report's root resource */
@property NSString *uti;
@property NSUInteger downloadSize;
@property NSUInteger downloadProgress;
@property BOOL isEnabled;
@property ReportImportStatus importStatus;
// TODO: use status message to display information instead of summary
@property NSString *statusMessage;
/** convenience method that returns YES if the import status is success or failed */
@property (readonly) BOOL isImportFinished;
@property NSMutableArray<ReportCache *> * cacheFiles;

- (instancetype)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)setPropertiesFromCoder:(NSCoder *)coder;

/**
 Set the properties of this report from key-value pairs in the given
 JSON descriptor dictionary.

 @return self
 */
- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor;

@end
