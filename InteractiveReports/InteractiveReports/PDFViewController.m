//
//  PDFViewController.m
//  InteractiveReports
//
//  Created by Tyler Burgett on 10/3/14.
//  Copyright (c) 2014 mil.nga. All rights reserved.
//

#import "PDFViewController.h"

@interface PDFViewController ()

@property BOOL isDismissed;

@end

@implementation PDFViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.isDismissed = NO;
}


- (void)viewDidAppear:(BOOL)animated
{
    if (!self.isDismissed) {
        ReaderDocument *document = [ReaderDocument withDocumentFilePath:self.report.url.path password:nil];
        
        if (document != nil) {
            ReaderViewController *readerViewController = [[ReaderViewController alloc] initWithReaderDocument:document];
            readerViewController.delegate = self;
            readerViewController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
            readerViewController.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:readerViewController animated:NO completion:nil];
        }
    }
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)dismissReaderViewController:(ReaderViewController *)viewController
{
    self.isDismissed = YES;
    [self dismissViewControllerAnimated:YES completion:^{
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

@end
