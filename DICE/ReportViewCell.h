//
//  ReportViewCell.h
//  InteractiveReports
//

#import <UIKit/UIKit.h>

@interface ReportViewCell : UICollectionViewCell

@property (strong, nonatomic) IBOutlet UIImageView *reportImage;
@property (strong, nonatomic) IBOutlet UITextView *reportTitle;
@property (weak, nonatomic) IBOutlet UITextView *reportDescription;

@end
