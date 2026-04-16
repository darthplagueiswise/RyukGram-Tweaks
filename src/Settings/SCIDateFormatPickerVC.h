#import <UIKit/UIKit.h>

@interface SCIDateFormatPickerVC : UIViewController <UITableViewDataSource, UITableViewDelegate>

/// Returns the formatted example string for the currently selected format.
+ (NSString *)currentFormatExample;

@end
