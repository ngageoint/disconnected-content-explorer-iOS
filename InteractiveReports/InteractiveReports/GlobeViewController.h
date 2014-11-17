//
//  GlobeViewController.h
//  InteractiveReports
//
//  Created by Robert St. John on 11/7/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol GlobeViewDelegate

- (void) dismissGlobeView;

@end

@interface GlobeViewController : UIViewController

@property (weak, nonatomic) id<GlobeViewDelegate> delegate;

@end
