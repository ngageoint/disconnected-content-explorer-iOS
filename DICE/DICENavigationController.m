//
//  DICENavigationDelegate.m
//  InteractiveReports
//
//  Created by Robert St. John on 12/2/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//


#import "DICENavigationController.h"

#import "ReportAPI.h"
#import "ReportResourceViewController.h"
#import "ResourceTypes.h"

@interface DICENavigationController ()

/**
 * the URL of the app that launched DICE using a dice:// URL
 * DICENavigation uses this to return to the referring app
 * when navigating away from the target report view.
 */
@property (strong, nonatomic) NSURL *referrerURL;

@end


@implementation DICENavigationController

+ (NSMutableDictionary *)parseQueryParametersFromURL:(NSURL *)url
{
    NSArray *paramList = [url.query componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"=&"]];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    for (int keyIndex = 0; keyIndex < [paramList count]; keyIndex += 2) {
        NSString *key = paramList[keyIndex];
        NSString *value = paramList[keyIndex + 1];
        [params setObject:value forKey:key];
    }
    return params;
}


- (void)viewDidLoad
{
    if ([self respondsToSelector:@selector(interactivePopGestureRecognizer)]) {
        self.interactivePopGestureRecognizer.enabled = NO;
    }
}


- (void)navigateToReportForURL:(NSURL *)target fromApp:(NSString *)bundleID
{
    NSDictionary *params = [DICENavigationController parseQueryParametersFromURL:target];
    NSString *srcScheme = params[@"srcScheme"];
    NSString *reportID = params[@"reportID"];
    NSString *resource = params[@"resource"];
    
    if (!reportID) {
        return;
    }
    
    Report *report = [[ReportAPI sharedInstance] reportForID:reportID];
    
    if (!report) {
        return;
    }
    
    if (srcScheme) {
        NSMutableString *srcURLStr = [NSMutableString stringWithFormat:@"%@://?srcScheme=dice", srcScheme];
        [params enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if (![key isEqualToString:@"srcScheme"]) {
                [srcURLStr appendFormat:@"&%@=%@", key, obj];
            }
        }];
        self.referrerURL = [NSURL URLWithString:srcURLStr];
        self.navigationItem.title = @"";
    }
    else {
        self.referrerURL = nil;
    }
    
    [self navigateToReport:report childResource:resource animated:NO];
}


- (void)navigateToReport:(Report *)report childResource:(NSString *)resourceName animated:(BOOL)animated
{
    ReportResourceViewController *reportView = [self.storyboard instantiateViewControllerWithIdentifier:@"reportResourceViewController"];
    reportView.report = report;
    if (!resourceName) {
        reportView.resource = report.url;
    }
    else {
        NSURL *resource = [report.url.baseURL URLByAppendingPathComponent:resourceName];
        reportView.resource = resource;
    }
    [self pushViewController:reportView animated:animated];
}


- (UIViewController *)popViewControllerAnimated:(BOOL)animated
{
    if (self.referrerURL) {
        UIViewController *topView = [super popViewControllerAnimated:NO];
        [[UIApplication sharedApplication] openURL:self.referrerURL];
        return topView;
    }
    return [super popViewControllerAnimated:animated];
}

@end
