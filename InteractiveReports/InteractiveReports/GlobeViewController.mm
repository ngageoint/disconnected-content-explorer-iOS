//
//  GlobeViewController.m
//  InteractiveReports
//
//  Created by Robert St. John on 11/7/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "GlobeViewController.h"
#import "G3MWidget_iOS.h"
#import "G3MBuilder_iOS.hpp"
#import "MeshRenderer.hpp"

//@class G3MWidget_iOS;


@interface GlobeViewController ()

@property (strong, nonatomic) IBOutlet G3MWidget_iOS *globeView;
@property (nonatomic) MeshRenderer *meshRenderer;

@end

@implementation GlobeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    G3MBuilder_iOS builder = G3MBuilder_iOS(self.globeView);
    builder.initializeWidget();
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// Start animation when view has appeared
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // Start the glob3 render loop
    [self.globeView startAnimation];
}

// Stop the animation when view has disappeared
- (void)viewDidDisappear:(BOOL)animated {
    // Stop the glob3 render loop
    [self.globeView stopAnimation];
    [super viewDidDisappear:animated];
}

// Release property
- (void)viewDidUnload {
    self.globeView = nil;
}

- (IBAction)onDone:(id)sender {
    if (self.delegate != nil) {
        [self.delegate dismissGlobeView];
    }
}


#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}


@end
