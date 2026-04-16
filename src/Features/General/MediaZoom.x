// Media zoom — long press on feed media to expand in full-screen viewer.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../ActionButton/SCIMediaActions.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import <objc/runtime.h>
#import <objc/message.h>

// IGFeedItemPageVideoCell declared in InstagramHeaders.h

static const void *kZoomGestureKey = &kZoomGestureKey;

static BOOL sciZoomEnabled(void) {
    return [SCIUtils getBoolPref:@"feed_media_zoom"];
}

// Walk up to the feed's outer collection view (skip carousel inner CVs)
static UICollectionView *sciFeedCollectionView(UIView *view) {
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:[UICollectionView class]]) {
            NSString *cls = NSStringFromClass([v class]);
            if (![cls containsString:@"Carousel"] && ![cls containsString:@"Page"])
                return (UICollectionView *)v;
        }
        v = v.superview;
    }
    return nil;
}

static NSInteger sciFeedSectionForView(UIView *view, UICollectionView *cv) {
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:[UICollectionViewCell class]]) {
            NSIndexPath *ip = [cv indexPathForCell:(UICollectionViewCell *)v];
            if (ip) return ip.section;
        }
        v = v.superview;
    }
    return -1;
}

// Extract IGMedia from sibling cells in the same section
static IGMedia *sciZoomFeedMedia(UIView *view) {
    Class mediaClass = NSClassFromString(@"IGMedia");
    if (!mediaClass) return nil;

    UICollectionView *cv = sciFeedCollectionView(view);
    if (!cv) return nil;

    NSInteger section = sciFeedSectionForView(view, cv);
    if (section < 0) return nil;

    for (UICollectionViewCell *cell in cv.visibleCells) {
        NSIndexPath *path = [cv indexPathForCell:cell];
        if (!path || path.section != section) continue;

        NSString *cls = NSStringFromClass([cell class]);
        if (![cls containsString:@"Photo"] && ![cls containsString:@"Video"]
            && ![cls containsString:@"Media"] && ![cls containsString:@"Page"]) continue;

        unsigned int count = 0;
        Class c = object_getClass(cell);
        while (c && c != [UICollectionViewCell class]) {
            Ivar *ivars = class_copyIvarList(c, &count);
            for (unsigned int i = 0; i < count; i++) {
                const char *type = ivar_getTypeEncoding(ivars[i]);
                if (!type || type[0] != '@') continue;
                @try {
                    id val = object_getIvar(cell, ivars[i]);
                    if (val && [val isKindOfClass:mediaClass]) { free(ivars); return (IGMedia *)val; }
                } @catch (__unused id e) {}
            }
            if (ivars) free(ivars);
            c = class_getSuperclass(c);
        }

        if ([cell respondsToSelector:@selector(mediaCellFeedItem)]) {
            id m = ((id(*)(id,SEL))objc_msgSend)(cell, @selector(mediaCellFeedItem));
            if (m && [m isKindOfClass:mediaClass]) return (IGMedia *)m;
        }
    }
    return nil;
}

// Carousel page index from the horizontal scroll view in the Page cell
static NSInteger sciZoomPageIndex(UIView *view) {
    UICollectionView *cv = sciFeedCollectionView(view);
    if (!cv) return 0;

    NSInteger section = sciFeedSectionForView(view, cv);
    if (section < 0) return 0;

    for (UICollectionViewCell *cell in cv.visibleCells) {
        NSIndexPath *path = [cv indexPathForCell:cell];
        if (!path || path.section != section) continue;
        if (![NSStringFromClass([cell class]) containsString:@"Page"]) continue;

        NSMutableArray *queue = [NSMutableArray arrayWithObject:cell];
        int scanned = 0;
        while (queue.count && scanned < 100) {
            UIView *cur = queue.firstObject; [queue removeObjectAtIndex:0]; scanned++;
            if ([cur isKindOfClass:[UIScrollView class]] && cur != cv) {
                UIScrollView *sv = (UIScrollView *)cur;
                CGFloat pageW = sv.bounds.size.width;
                if (pageW > 100 && sv.contentSize.width > pageW * 1.5)
                    return (NSInteger)round(sv.contentOffset.x / pageW);
            }
            for (UIView *s in cur.subviews) [queue addObject:s];
        }
    }
    return 0;
}

static void sciZoomFired(UILongPressGestureRecognizer *g) {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!sciZoomEnabled()) return;

    UIView *view = g.view;
    IGMedia *media = sciZoomFeedMedia(view);
    if (!media) return;

    NSString *caption = [SCIMediaActions captionForMedia:media];

    if ([SCIMediaActions isCarouselMedia:media]) {
        NSArray *children = [SCIMediaActions carouselChildrenForMedia:media];
        NSMutableArray *items = [NSMutableArray array];
        for (id child in children) {
            NSURL *v = [SCIUtils getVideoUrlForMedia:(IGMedia *)child];
            NSURL *p = [SCIUtils getPhotoUrlForMedia:(IGMedia *)child];
            if (!v && !p) p = [SCIMediaActions bestURLForMedia:child];
            if (v || p) [items addObject:[SCIMediaViewerItem itemWithVideoURL:v photoURL:p caption:caption]];
        }
        if (items.count) {
            NSInteger idx = sciZoomPageIndex(view);
            if (idx < 0 || idx >= (NSInteger)items.count) idx = 0;
            [SCIMediaViewer showItems:items startIndex:idx];
            return;
        }
    }

    NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:media];
    NSURL *photoUrl = [SCIUtils getPhotoUrlForMedia:media];
    if (!videoUrl && !photoUrl) photoUrl = [SCIMediaActions bestURLForMedia:media];
    if (!videoUrl && !photoUrl) return;

    [SCIMediaViewer showWithVideoURL:videoUrl photoURL:photoUrl caption:caption];
}

// MARK: - Gesture setup

@interface _SCIZoomTarget : NSObject @end
@implementation _SCIZoomTarget
- (void)fired:(UILongPressGestureRecognizer *)g { sciZoomFired(g); }
@end

static void sciAddZoomGesture(UIView *view) {
    if (objc_getAssociatedObject(view, kZoomGestureKey)) return;

    _SCIZoomTarget *target = [_SCIZoomTarget new];
    objc_setAssociatedObject(view, kZoomGestureKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:target action:@selector(fired:)];
    gesture.minimumPressDuration = 0.5;
    [view addGestureRecognizer:gesture];
}

// MARK: - Hooks

%hook IGFeedPhotoView
- (void)didMoveToSuperview {
    %orig;
    if (self.superview) sciAddZoomGesture(self);
}
%end

%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)didMoveToSuperview {
    %orig;
    if (((UIView *)self).superview) sciAddZoomGesture((UIView *)self);
}
%end

%hook IGFeedItemPagePhotoCell
- (void)didMoveToSuperview {
    %orig;
    if (self.superview) sciAddZoomGesture((UIView *)self);
}
%end

%hook IGFeedItemPageVideoCell
- (void)didMoveToSuperview {
    %orig;
    if (self.superview) sciAddZoomGesture((UIView *)self);
}
%end
