//
//  Report+CoreDataProperties.m
//  DICE
//
//  Created by Robert St. John on 7/5/17.
//  Copyright © 2017 mil.nga. All rights reserved.
//

#import "Report+CoreDataProperties.h"

@implementation Report (CoreDataProperties)

+ (NSFetchRequest<Report *> *)fetchRequest {
	return [[NSFetchRequest alloc] initWithEntityName:@"Report"];
}

@dynamic baseDirUrl;
@dynamic contentId;
@dynamic importDirUrl;
@dynamic importStatus;
@dynamic isEnabled;
@dynamic lat;
@dynamic lon;
@dynamic remoteSourceUrl;
@dynamic rootFileName;
@dynamic sourceFileUrl;
@dynamic statusMessage;
@dynamic summary;
@dynamic thumbnailUrl;
@dynamic tileThumbnailUrl;
@dynamic title;
@dynamic uti;

@end
