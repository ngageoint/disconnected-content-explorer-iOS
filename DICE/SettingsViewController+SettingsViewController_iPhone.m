//
//  SettingsViewController+SettingsViewController_iPhone.m
//  DICE
//
//  Created by Robert St. John on 4/3/15.
//  Copyright (c) 2015 mil.nga. All rights reserved.
//

#import "SettingsViewController.h"

@interface SettingsViewController (SettingsViewController_iPhone)

- (IBAction)onDoneButtonTapped:(id)sender;

@end


@implementation SettingsViewController (SettingsViewController_iPhone)

- (IBAction)onDoneButtonTapped:(id)sender
{
    [self dismissViewControllerAnimated:true completion:nil];
}

@end
