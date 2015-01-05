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
@property (nonatomic, strong) Report *report;

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
        /*
         * Note: If we ever change the directory where PDF documents are stored, this library writes out
         * some Plist files in the Application Support directory that retains a path component of PDFs
         * it tried to open based on the last path component file name of the PDF.  This will cause the 
         * app to crash because the file name in the Plist will not be valid and results in a null document
         * object within the ReaderDocument.
         *
         * See ReaderDocument -> + (ReaderDocument *)unarchiveFromFileName:(NSString *) password:(NSString *)
         * which produces the invalid PDF path.
         */
        ReaderDocument *document = [ReaderDocument withDocumentFilePath:self.report.url.absoluteURL.path password:nil];
        if (document != nil) {
            ReaderViewController *readerViewController = [[ReaderViewController alloc] initWithReaderDocument:document];
            readerViewController.delegate = self;
            readerViewController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
            readerViewController.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:readerViewController animated:NO completion:nil];
        }
    }
}


- (void)handleResource:(NSURL *)resource forReport:(Report *)report
{
    self.report = report;
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
