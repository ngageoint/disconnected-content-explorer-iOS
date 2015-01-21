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
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *nameWidthConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *descHeightConstraint;

@property (weak, nonatomic) KMLPlacemark *placemark;

@end


@implementation KMLBalloonViewController

- (void)logLayout
{
    NSLog(@"KML balloon: %@", NSStringFromCGRect(self.view.frame));
    NSLog(@"KML balloon system size: %@", NSStringFromCGSize([self.view systemLayoutSizeFittingSize:UILayoutFittingCompressedSize]));
    NSLog(@"KML name: %@", NSStringFromCGRect(_nameLabel.frame));
    NSLog(@"KML name intrinsic: %@", NSStringFromCGSize([_nameLabel intrinsicContentSize]));
    NSLog(@"KML description: %@", NSStringFromCGRect(_descWebView.frame));
    NSLog(@"KML description scroll: %@", NSStringFromCGRect(_descWebView.scrollView.frame));
    NSLog(@"KML description content: %@", NSStringFromCGSize(_descWebView.scrollView.contentSize));
    NSLog(@"KML description intrinsic: %@", NSStringFromCGSize([_descWebView intrinsicContentSize]));
    NSLog(@"KML description system: %@", NSStringFromCGSize([_descWebView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize]));
}

- (id)initWithPlacemark:(KMLPlacemark *)placemark
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.placemark = placemark;
    
    return self;
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
    CGSize intrinsicSize = [_nameLabel intrinsicContentSize];
    _nameWidthConstraint.constant = intrinsicSize.width;
    
    NSString *desc = @"";
    if (_placemark.descriptionValue && _placemark.descriptionValue.length > 0) {
        desc = _placemark.descriptionValue;
        _descHeightConstraint.constant = 1.0;
        [_descWebView loadHTMLString:desc baseURL:nil];
    }
    else {
        [_descWebView removeFromSuperview];
    }
    
    [self logLayout];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    NSLog(@"web view did finish load");

    NSString *jsHeight = [_descWebView stringByEvaluatingJavaScriptFromString:@"document.body.offsetHeight"];
    NSLog(@"javascript height: %@", jsHeight);
    
    _descHeightConstraint.constant = _descWebView.scrollView.contentSize.height;
    [self.view setNeedsUpdateConstraints];
    
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

    self.contentSizeForViewInPopover = [self.view systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    
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
