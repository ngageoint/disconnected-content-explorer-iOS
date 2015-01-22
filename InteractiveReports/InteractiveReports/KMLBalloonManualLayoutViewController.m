//
//  KMLBalloonManualLayoutViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 1/20/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "KMLBalloonManualLayoutViewController.h"


#define MARGIN 8.0f
#define SPACING 5.0f
#define WIDTH_MIN 240.0f
#define WIDTH_MAX 480.0f
#define HEIGHT_MIN 48.0f
#define HEIGHT_MAX 320.0f

@interface KMLBalloonManualLayoutViewController () <UIWebViewDelegate>

@property (weak, nonatomic) KMLPlacemark *placemark;
@property (strong, nonatomic) UILabel *nameLabel;
@property (strong, nonatomic) UIWebView *descWebView;

@end


@implementation KMLBalloonManualLayoutViewController

- (id)initWithPlacemark:(KMLPlacemark *)placemark
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.placemark = placemark;
    
    self.nameLabel = [UILabel new];
    NSString *name = _placemark.name;
    if (!name) {
        name = [NSString stringWithFormat:@"%@ Placemark", [_placemark.geometry class]];
    }
    _nameLabel.text = name;
    
    if (placemark.descriptionValue) {
        self.descWebView = [UIWebView new];
        _descWebView.delegate = self;
        _descWebView.scalesPageToFit = NO;
        _descWebView.contentScaleFactor = 2.0;
    }
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    [self layoutViews];
    
    if (_descWebView) {
        [_descWebView loadHTMLString:_placemark.descriptionValue baseURL:nil];
    }
    
    // TODO: support text from BalloonStyle element
}

- (void)layoutViews
{
    [_nameLabel sizeToFit];
    
    CGFloat width = fmaxf(_nameLabel.bounds.size.width, WIDTH_MIN);
    CGFloat height = fmaxf(_nameLabel.bounds.size.height, HEIGHT_MIN);
    
    [self.view addSubview:_nameLabel];
    
    if (_descWebView) {
        _nameLabel.frame = CGRectOffset(_nameLabel.bounds, MARGIN, MARGIN);
        _descWebView.bounds = CGRectMake(0, 0, width, height);
        _descWebView.frame = CGRectMake(MARGIN, CGRectGetMaxY(_nameLabel.frame) + SPACING, width, height);
        [self.view addSubview:_descWebView];
        height = fmaxf(height, CGRectGetMaxY(_descWebView.frame));
    }
    else {
        CGFloat horizontalCenter = width / 2.0 - _nameLabel.bounds.size.width / 2.0;
        CGFloat verticalCenter = height / 2.0;
        _nameLabel.frame = CGRectOffset(_nameLabel.bounds, horizontalCenter, verticalCenter);
    }
    
    CGRect rootBounds = CGRectMake(0, 0, width + 2 * MARGIN, height + 2 * MARGIN);
    self.view.bounds = rootBounds;
    self.preferredContentSize = rootBounds.size;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    CGFloat heightChange = _descWebView.scrollView.contentSize.height - _descWebView.bounds.size.height;
    if (heightChange <= 0) {
        return;
    }
    _descWebView.frame = CGRectMake(_descWebView.frame.origin.x, _descWebView.frame.origin.y,
        _descWebView.frame.size.width, _descWebView.frame.size.height + heightChange);
    self.view.bounds = CGRectMake(0.0, 0.0, self.view.bounds.size.width, self.view.bounds.size.height + heightChange);
    self.contentSizeForViewInPopover = self.preferredContentSize = self.view.bounds.size;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
