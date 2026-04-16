// SCIRepostSheet — download media, save to Photos, open IG's creation flow.

#import <UIKit/UIKit.h>

@interface SCIRepostSheet : NSObject

/// Download media, save to Photos, open IG's creation flow.
+ (void)repostWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL;

@end
