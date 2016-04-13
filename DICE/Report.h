//
//  Report.h
//  InteractiveReports
//

#import <Foundation/Foundation.h>

@interface Report : NSObject

@property (nonatomic, strong) NSString *reportID;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *summary;
@property (nonatomic, strong) NSString *thumbnail;
@property (nonatomic, strong) NSString *tileThumbnail;
@property (nonatomic, strong) NSString *fileExtension;
@property (nonatomic, strong) NSString *error;
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSURL *sourceFile;
@property (nonatomic) double lat;
@property (nonatomic) double lon;
@property (nonatomic) int totalNumberOfFiles;
@property (nonatomic) int progress;
@property (nonatomic) long downloadSize;
@property (nonatomic) long downloadProgress;
@property (nonatomic) BOOL isEnabled;

- (instancetype) initWithTitle:(NSString *)title;

@end
