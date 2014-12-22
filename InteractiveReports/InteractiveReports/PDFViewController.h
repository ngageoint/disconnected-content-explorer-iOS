//
//  PDFViewController.h
//  InteractiveReports
//
//  Created by Tyler Burgett on 10/3/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "ReaderViewController.h"
#import "Report.h"
#import "ResourceTypes.h"

@interface PDFViewController : UIViewController <ResourceHandler, ReaderViewControllerDelegate>

@end
