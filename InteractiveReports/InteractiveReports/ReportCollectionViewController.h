//
//  ReportCollectionViewController.h
//  InteractiveReports
//
//  Created by Robert St. John on 11/18/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Report.h"

@interface ReportCollectionViewController : UIViewController

// TODO: get rid of this and let app delegate handle it
@property (nonatomic) BOOL didBecomeActive;
@property (strong, nonatomic) NSString *srcScheme;
@property (strong, nonatomic) NSDictionary *urlParams;
@property (strong, nonatomic) NSString *reportID;

@end
