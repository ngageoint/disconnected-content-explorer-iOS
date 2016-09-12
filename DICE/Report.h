//
//  Report.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>
#import "ReportCache.h"

@interface Report : NSObject

@property (nonatomic) NSString *reportID;
@property (nonatomic) NSString *title;
@property (nonatomic) NSString *summary;
@property (nonatomic) NSString *thumbnail;
@property (nonatomic) NSString *tileThumbnail;
@property (nonatomic) NSString *error;
/** the url of the resource that a client should load first when viewing this report */
@property (nonatomic) NSURL *url;
/** the uniform type identifier of the report's root resource */
@property (nonatomic) CFStringRef uti;
@property (nonatomic) NSNumber *lat;
@property (nonatomic) NSNumber *lon;
// TODO: remove these
@property (nonatomic) int totalNumberOfFiles;
@property (nonatomic) int progress;
@property (nonatomic) long downloadSize;
@property (nonatomic) long downloadProgress;
@property (nonatomic) BOOL isEnabled;
@property (nonatomic) NSMutableArray<ReportCache *> * cacheFiles;

- (instancetype)initWithTitle:(NSString *)title;

/**
 Set the properties of this report from key-value pairs in the given
 JSON descriptor dictionary.

 @return self
 */
- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor;

@end
