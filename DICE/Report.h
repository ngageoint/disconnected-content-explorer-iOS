//
//  Report.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>

@interface Report : NSObject

@property (nonatomic) NSString *reportID;
@property (nonatomic) NSString *title;
@property (nonatomic) NSString *summary;
@property (nonatomic) NSString *thumbnail;
@property (nonatomic) NSString *tileThumbnail;
/**
 @todo change to UTI, or remove completely
 */
@property (nonatomic) NSString *fileExtension;
@property (nonatomic) NSString *error;
@property (nonatomic) NSURL *url;
@property (nonatomic) NSURL *sourceFile;
@property (nonatomic) NSNumber *lat;
@property (nonatomic) NSNumber *lon;
@property (nonatomic) int totalNumberOfFiles;
@property (nonatomic) int progress;
@property (nonatomic) BOOL isEnabled;

- (instancetype)initWithTitle:(NSString *)title;

/**
 Set the properties of this report from key-value pairs in the given
 JSON descriptor dictionary.

 @return self
 */
- (instancetype)setPropertiesFromJsonDescriptor:(NSDictionary *)descriptor;

@end
