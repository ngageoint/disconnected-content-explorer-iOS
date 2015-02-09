//
//  DICENavigationDelegate.h
//  InteractiveReports
//
//  Created by Robert St. John on 12/2/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "Report.h"

@interface DICENavigationController : UINavigationController

- (void)navigateToReport:(Report *)report childResource:(NSString *)resourceName animated:(BOOL)animated;
- (void)navigateToReportForURL:(NSURL *)target fromApp:(NSString *)bundleID;

@end
