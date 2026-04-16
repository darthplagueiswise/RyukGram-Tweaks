// SCIMediaViewer — full-screen media viewer. Supports single items and carousels.

#import <UIKit/UIKit.h>

/// One media item to display.
@interface SCIMediaViewerItem : NSObject
@property (nonatomic, strong) NSURL *videoURL;   // nil for photos
@property (nonatomic, strong) NSURL *photoURL;   // nil for videos
@property (nonatomic, copy)   NSString *caption;
+ (instancetype)itemWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL caption:(NSString *)caption;
@end

@interface SCIMediaViewer : NSObject

/// Show a single media item.
+ (void)showItem:(SCIMediaViewerItem *)item;

/// Show multiple items (carousel). Starts at the given index.
+ (void)showItems:(NSArray<SCIMediaViewerItem *> *)items startIndex:(NSUInteger)index;

/// Convenience: auto-detect video vs photo for a single item.
+ (void)showWithVideoURL:(NSURL *)videoURL photoURL:(NSURL *)photoURL caption:(NSString *)caption;

@end
