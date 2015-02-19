//
//  ListCollectionView.h
//  InteractiveReports
//
//  Created by Robert St. John on 11/20/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#ifndef InteractiveReports_ReportCollectionView_h
#define InteractiveReports_ReportCollectionView_h

#import "Report.h"


@protocol ReportCollectionViewDelegate

- (void)reportSelectedToView:(Report *)report;

@end


@protocol ReportCollectionView

// TODO: make this non-mutable and fix view classes that attempt to mutate it
@property (strong, nonatomic) NSArray *reports;
@property (strong, nonatomic) id<ReportCollectionViewDelegate> delegate;

@end


#endif
