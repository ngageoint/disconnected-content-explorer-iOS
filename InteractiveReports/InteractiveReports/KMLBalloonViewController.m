//
//  KMLBalloonContentViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 1/17/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import <MapKit/MapKit.h>

#import "KMLBalloonViewController.h"

@interface KMLBalloonViewController () <UIWebViewDelegate>

@property (strong, nonatomic) IBOutlet UIView *view;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UIWebView *descWebView;

@end

@implementation KMLBalloonViewController

CGSize idealSizeToShowLabel;

- (void)logLayout
{
    NSLog(@"KML balloon: %@", NSStringFromCGRect(self.view.frame));
    NSLog(@"KML balloon ideal: %@", NSStringFromCGSize(idealSizeToShowLabel));
    NSLog(@"KML name: %@", NSStringFromCGRect(_nameLabel.frame));
    NSLog(@"KML name intrinsic: %@", NSStringFromCGSize([_nameLabel intrinsicContentSize]));
    NSLog(@"KML description: %@", NSStringFromCGRect(_descWebView.frame));
    NSLog(@"KML description scroll: %@", NSStringFromCGRect(_descWebView.scrollView.frame));
    NSLog(@"KML description content: %@", NSStringFromCGSize(_descWebView.scrollView.contentSize));
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _descWebView.delegate = self;
}

- (void)viewWillAppear:(BOOL)animated
{
    NSLog(@"view will appear");
    NSString *name = _placemark.name;
    if (!name) {
        name = [NSString stringWithFormat:@"%@ Placemark", [_placemark.geometry class]];
    }
    _nameLabel.text = name;
    [_nameLabel sizeToFit];
    
    NSString *desc = @"";
    if (_placemark.descriptionValue && _placemark.descriptionValue.length > 0) {
        desc = _placemark.descriptionValue;
        _descWebView.bounds = CGRectMake(0.0, 0.0, _nameLabel.bounds.size.width, _nameLabel.bounds.size.height * 2.0);
        [_descWebView loadHTMLString:desc baseURL:nil];
    }

    idealSizeToShowLabel = [self.view systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    self.contentSizeForViewInPopover = idealSizeToShowLabel;
    self.view.bounds = CGRectMake(0.0, 0.0, idealSizeToShowLabel.width, idealSizeToShowLabel.height);
    
    [self logLayout];
}

- (void)viewDidDisappear:(BOOL)animated
{
    _nameLabel.text = @"";
    _nameLabel.bounds = CGRectZero;
    [_descWebView loadHTMLString:@"" baseURL:nil];
    _descWebView.bounds = CGRectZero;
    
    [super viewDidDisappear:animated];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    NSLog(@"web view did finish load");
    
    [self logLayout];
    
    NSString *jsResult = [_descWebView stringByEvaluatingJavaScriptFromString:@"document.body.offsetHeight"];
    NSLog(@"javascript height: %@", jsResult);
    
    NSLog(@"web view sized to fit");

    CGRect currentBounds = self.view.bounds;
    CGPoint currentOrig = currentBounds.origin;
    CGSize currentSize = currentBounds.size;
    self.view.bounds = CGRectMake(currentOrig.x, currentOrig.y, currentSize.width, currentSize.height + [jsResult floatValue]);
    self.contentSizeForViewInPopover = self.view.bounds.size;
    
    [self logLayout];
}

- (void)updateViewConstraints
{
    [super updateViewConstraints];
    
    NSLog(@"update constraints");
    [self logLayout];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    
    NSLog(@"will layout subviews");
    [self logLayout];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    NSLog(@"did layout subviews");
    [self logLayout];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
