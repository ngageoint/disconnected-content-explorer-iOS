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
#define HEIGHT_MIN 30.0f
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
    
    self.descWebView = [UIWebView new];
    
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSString *name = _placemark.name;
    if (!name) {
        name = [NSString stringWithFormat:@"%@ Placemark", [_placemark.geometry class]];
    }
    
    _nameLabel.text = name;
    [_nameLabel sizeToFit];
    _nameLabel.frame = CGRectMake(MARGIN, MARGIN, _nameLabel.bounds.size.width, _nameLabel.bounds.size.height);
    [self.view addSubview:_nameLabel];
    
    if (_placemark.descriptionValue && _placemark.descriptionValue.length > 0) {
        [_descWebView loadHTMLString:_placemark.descriptionValue baseURL:nil];
    }
    
    CGRect rootBounds = CGRectInset(_nameLabel.bounds, -MARGIN, -MARGIN);
    rootBounds = CGRectOffset(rootBounds, MARGIN, MARGIN);
    self.view.bounds = rootBounds;
    self.contentSizeForViewInPopover = self.preferredContentSize = self.view.bounds.size;
    
    // TODO: support text from BalloonStyle element
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
