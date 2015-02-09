//
//  NoteViewController.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>
#import "Report.h"

@interface NoteViewController : UIViewController

@property (strong, nonatomic) IBOutlet UITextView *noteTextView;
@property (strong, nonatomic) Report *report;
@property (strong, nonatomic) NSString *noteFilePath;

- (IBAction)saveNote:(id)sender;
- (IBAction)cancel:(id)sender;

@end
