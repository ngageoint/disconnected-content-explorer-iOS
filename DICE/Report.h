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


@interface Report : NSObject // TODO: <NSCoding>

// TODO: add ReportType reference to materialize more easily after initial import?
// @property (nonatomic) NSString *reportTypeKey; // or something

// provided by descriptor/content author
@property (nonatomic) NSString *reportID;
@property (nonatomic) NSString *title;
@property (nonatomic) NSString *summary;
@property (nonatomic) NSString *thumbnail;
@property (nonatomic) NSString *tileThumbnail;
@property (nonatomic) NSNumber *lat;
@property (nonatomic) NSNumber *lon;

// provided by app during/after import
/** the url of the resource from which this report was downloaded, or nil */
@property (nonatomic) NSURL *remoteSource;
/** the file url of the resource from which this report was first imported, i.e., the url passed to ReportStore:attemptToImportReportFromResource: */
@property (nonatomic) NSURL *sourceFile;
/** a container directory ReportStore creates to wrap extra information with report package's content */
@property (nonatomic) NSURL *importDir;
/**
 * the file url of the base directory for this report's content;
 * nil if the content is a stand-alone resource in the import directory,
 * e.g., a PDF or MS Office file
 */
@property (nonatomic) NSURL *baseDir;
/** the file url of the resource that a client should load first when viewing this report */
@property (nonatomic) NSURL *rootFile;
/** the uniform type identifier of the report's root resource */
@property (nonatomic) CFStringRef uti;
@property (nonatomic) NSUInteger downloadSize;
@property (nonatomic) NSUInteger downloadProgress;
@property (nonatomic) BOOL isEnabled;
@property (nonatomic) ReportImportStatus importStatus;
// TODO: use status message to display information instead of summary
@property (nonatomic) NSString *statusMessage;
/** convenience method that returns YES if the import status is success or failed */
@property (readonly, nonatomic) BOOL isImportFinished;
@property (nonatomic) NSMutableArray<ReportCache *> * cacheFiles;

/**
 Set the properties of this report from key-value pairs in the given
 JSON descriptor dictionary.

 @return self
 */
- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor;

@end
