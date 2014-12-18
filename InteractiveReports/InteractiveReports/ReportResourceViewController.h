//
//  ReportLinkedResourceViewController.h
//  InteractiveReports
//
//  Created by Robert St. John on 11/21/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "Report.h"


@interface ReportResourceViewController : UIViewController

@property (weak, nonatomic) Report *report;
@property (weak, nonatomic) NSURL *resource;

@end
