//
//  Report+CoreDataProperties.h
//  DICE
//
//  Created by Robert St. John on 7/5/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "Report.h"


NS_ASSUME_NONNULL_BEGIN

@interface Report (CoreDataProperties)

+ (NSFetchRequest<Report *> *)fetchRequest;

@property (nullable, nonatomic, copy) NSString *baseDirUrl;
@property (nullable, nonatomic, copy) NSString *contentId;
@property (nullable, nonatomic, copy) NSString *importDirUrl;
@property (nonatomic) int16_t importStatus;
@property (nonatomic) BOOL isEnabled;
@property (nullable, nonatomic, copy) NSDecimalNumber *lat;
@property (nullable, nonatomic, copy) NSDecimalNumber *lon;
@property (nullable, nonatomic, copy) NSString *remoteSourceUrl;
@property (nullable, nonatomic, copy) NSString *rootFileName;
@property (nullable, nonatomic, copy) NSString *sourceFileUrl;
@property (nullable, nonatomic, copy) NSString *statusMessage;
@property (nullable, nonatomic, copy) NSString *summary;
@property (nullable, nonatomic, copy) NSString *thumbnailUrl;
@property (nullable, nonatomic, copy) NSString *tileThumbnailUrl;
@property (nullable, nonatomic, copy) NSString *title;
@property (nullable, nonatomic, copy) NSString *uti;

@end

NS_ASSUME_NONNULL_END
