#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Gives the settings search bar an opaque pill when liquid glass is off.
@interface SCISearchBarStyler : NSObject
+ (void)styleSearchBar:(UISearchBar *)searchBar;
@end

NS_ASSUME_NONNULL_END
