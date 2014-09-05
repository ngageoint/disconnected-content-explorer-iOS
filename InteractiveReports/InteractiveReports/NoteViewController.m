//
//  NoteViewController.m
//  InteractiveReports
//

#import "NoteViewController.h"

@interface NoteViewController ()

@end

@implementation NoteViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = [paths objectAtIndex:0]; //Get the docs directory
    
    _noteFilePath = [documentsPath stringByAppendingString:[NSString stringWithFormat:@"/notes/%@.txt", _report.title]];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:_noteFilePath isDirectory:NO]) {
        NSString *fileContents =  [NSString stringWithContentsOfFile:_noteFilePath
                                                            encoding:NSUTF8StringEncoding
                                                               error:NULL];
        self.noteTextView.text = fileContents;
    }
    
    [self.noteTextView becomeFirstResponder];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


// Notes get saved into the notes folder in the app's Documents directory.
- (IBAction)saveNote:(id)sender {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsPath = [paths objectAtIndex:0]; //Get the docs directory
    
    NSFileManager *fm = [[NSFileManager alloc] init];
    NSError *error;
    
    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:[documentsPath stringByAppendingPathComponent:@"notes"] isDirectory:&isDir];
    if (!exists) {
        [[NSFileManager defaultManager] createDirectoryAtPath:[documentsPath stringByAppendingPathComponent:@"notes"] withIntermediateDirectories:NO attributes:nil error:&error];
    }
    
    NSString *filePath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"/notes/%@.txt", self.report.title]]; //Add the file name
    [self.noteTextView.text writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    [self dismissViewControllerAnimated:YES completion:nil];
}


- (IBAction)cancel:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}


- (BOOL)prefersStatusBarHidden {
    return YES;
}

@end
