//
//  ReportMetaData.h
//  DICE
//
//  Created by Robert St. John on 8/5/15.
//  Copyright (c) 2015 National Geospatial-Intelligence Agency. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Report.h"


@interface ParseJsonOperation : NSOperation

@property (nonatomic) NSURL *jsonUrl;
@property (readonly) NSDictionary *parsedJsonDictionary;

@end