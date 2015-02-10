//
//  DisclaimerViewController.m
//  DICE
//
//  Created by Tyler Burgett on 2/9/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "DisclaimerViewController.h"

@interface DisclaimerViewController ()

@end

@implementation DisclaimerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
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

- (IBAction)agreeTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}


- (IBAction)exitTapped:(id)sender {
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
