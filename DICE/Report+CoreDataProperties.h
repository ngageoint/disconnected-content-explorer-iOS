//
//  Report+CoreDataProperties.h
//  DICE
//
//  Created by Robert St. John on 7/7/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "Report.h"


NS_ASSUME_NONNULL_BEGIN

@interface Report (CoreDataProperties)

+ (NSFetchRequest<Report *> *)fetchRequest;

@property (nullable, nonatomic, copy) NSString *baseDirName;
@property (nullable, nonatomic, copy) NSString *contentId;
@property (nullable, nonatomic, copy) NSDate *dateAdded;
@property (nullable, nonatomic, copy) NSDate *dateLastAccessed;
@property (nonatomic) int64_t downloadProgress;
@property (nonatomic) int64_t downloadSize;
@property (nonatomic) int16_t extractPercent;
@property (nullable, nonatomic, retain) NSURL *importDir;
@property (nullable, nonatomic, copy) NSString *importDirUrl;
@property (nonatomic) int16_t importStatus;
@property (nonatomic) BOOL isEnabled;
@property (nullable, nonatomic, copy) NSDecimalNumber *lat;
@property (nullable, nonatomic, copy) NSDecimalNumber *lon;
@property (nullable, nonatomic, retain) NSURL *remoteSource;
@property (nullable, nonatomic, copy) NSString *remoteSourceUrl;
@property (nullable, nonatomic, copy) NSString *reportTypeId;
@property (nullable, nonatomic, copy) NSString *rootFilePath;
@property (nullable, nonatomic, retain) NSURL *sourceFile;
@property (nullable, nonatomic, copy) NSString *sourceFileUrl;
@property (nullable, nonatomic, copy) NSString *statusMessage;
@property (nullable, nonatomic, copy) NSString *summary;
@property (nullable, nonatomic, copy) NSString *thumbnailPath;
@property (nullable, nonatomic, copy) NSString *tileThumbnailPath;
@property (nullable, nonatomic, copy) NSString *title;
@property (nullable, nonatomic, copy) NSString *uti;

@end

NS_ASSUME_NONNULL_END
