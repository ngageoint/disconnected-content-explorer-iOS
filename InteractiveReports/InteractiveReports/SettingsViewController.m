//
//  SettingsViewController.m
//  InteractiveReports
//
// The title of this class is a bit off at the moment, since it is just attribution and version info.
// Theme switcher, and default view settings coming soon(TM).
//

#import "SettingsViewController.h"

@interface SettingsViewController ()

@end

@implementation SettingsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}


// The values for version and build can be updated in the project plist.
- (void)viewDidLoad
{
    [super viewDidLoad];
    NSDictionary *infoDictionary = [[NSBundle mainBundle]infoDictionary];
    
    NSString *build = infoDictionary[(NSString*)kCFBundleVersionKey];
    NSString *version = infoDictionary[@"CFBundleShortVersionString"];
    
    _versionLabel.text = [NSString stringWithFormat:@"DICE version %@.%@", version, build];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
