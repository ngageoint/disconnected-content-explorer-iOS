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

/** the uniform type identifier of the report's root resource */
@property (nonatomic) NSUInteger downloadSize;
@property (nonatomic) NSUInteger downloadProgress;

#pragma mark - non-persistent properties

// convenience properties for setting persistent url properties
// TODO: core_data: transient properties or custom ivars?
/** the url of the resource from which this report was downloaded, or nil */
@property (strong, nonatomic) NSURL *remoteSource;
/** the file url of the resource from which this report was first imported, i.e., the url passed to ReportStore:attemptToImportReportFromResource: */
@property (strong, nonatomic) NSURL *sourceFile;
/** a container directory ReportStore creates to wrap extra information with report package's content */
@property (strong, nonatomic) NSURL *importDir;
/**
 * the file url of the base directory for this report's content;
 * nil if the content is a stand-alone resource in the import directory,
 * e.g., a PDF or MS Office file
 */
@property (strong, nonatomic) NSURL *baseDir;
/** the file url of the resource that a client should load first when viewing this report */
@property (strong, nonatomic) NSURL *rootFile;
@property (strong, nonatomic) NSURL *thumbnail;
@property (strong, nonatomic) NSURL *tileThumbnail;

@property (readonly) BOOL isImportFinished;
@property NSMutableArray<ReportCache *> * cacheFiles;

/**
 Set the properties of this report from key-value pairs in the given
 JSON descriptor dictionary.

 @return self
 */
- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor;

@end

#import "Report+CoreDataProperties.h"
