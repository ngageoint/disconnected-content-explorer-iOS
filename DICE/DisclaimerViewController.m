//
//  DisclaimerViewController.m
//  DICE
//
//  Created by Tyler Burgett on 2/9/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "DisclaimerViewController.h"


@interface DisclaimerViewController ()

- (IBAction)agreeTapped:(id)sender;
- (IBAction)exitTapped:(id)sender;
- (IBAction)switchChanged:(id)sender;

@end


@implementation DisclaimerViewController

+ (BOOL)shouldShowDisclaimer {
    return ![[NSUserDefaults standardUserDefaults] boolForKey:@"preventDisclaimer"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)agreeTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)exitTapped:(id)sender {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"preventDisclaimer"];
    exit(0);
}

- (IBAction)switchChanged:(UISwitch*)sender {
    if ([sender isOn]) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"preventDisclaimer"];
    } else {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"preventDisclaimer"];
    }
}


@end
