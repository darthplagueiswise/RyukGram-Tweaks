// View highlight cover — opens the cover image in the full-screen media viewer.

#import "../../Utils.h"
#import "../../Downloader/Download.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// Find the IGStoryTrayCell with an active long-press gesture
static UIView *sciFindLongPressedCell(UIView *root) {
    Class cellCls = NSClassFromString(@"IGStoryTrayCell");
    if (!cellCls) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:cellCls]) {
            for (UIGestureRecognizer *gr in v.gestureRecognizers) {
                if ([gr isKindOfClass:[UILongPressGestureRecognizer class]] &&
                    (gr.state == UIGestureRecognizerStateBegan || gr.state == UIGestureRecognizerStateChanged))
                    return v;
            }
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return nil;
}

// Find the IGImageView inside a specific cell
static UIImage *sciCoverImageFromCell(UIView *cell) {
    if (!cell) return nil;
    Class igImageView = NSClassFromString(@"IGImageView");
    if (!igImageView) igImageView = [UIImageView class];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:cell];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:igImageView] && [v isKindOfClass:[UIImageView class]]) {
            UIImage *img = [(UIImageView *)v image];
            if (img && img.size.width > 10) return img;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return nil;
}

static void sciViewCoverImage(UIImage *image) {
    if (!image) {
        [SCIUtils showErrorHUDWithDescription:SCILocalized(@"Could not find cover image")];
        return;
    }

    // Save to temp and open in the media viewer
    NSData *data = UIImageJPEGRepresentation(image, 1.0);
    if (!data) return;
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"cover_%@.jpg", [[NSUUID UUID] UUIDString]]];
    [data writeToFile:tmpPath atomically:YES];
    NSURL *tmpURL = [NSURL fileURLWithPath:tmpPath];
    [SCIMediaViewer showWithVideoURL:nil photoURL:tmpURL caption:nil];
}

// Stored reference to the long-pressed cell (captured at presentation time)
static __weak UIView *sciLongPressedHighlightCell = nil;

static void (*orig_present)(id, SEL, id, BOOL, id);
static void new_present(id self, SEL _cmd, id vc, BOOL animated, id completion) {
    if ([SCIUtils getBoolPref:@"download_highlight_cover"] &&
        [NSStringFromClass([vc class]) containsString:@"ActionSheet"] &&
        [NSStringFromClass([self class]) containsString:@"Profile"]) {

        // Capture the long-pressed cell NOW while the gesture is still active
        UIView *cell = sciFindLongPressedCell([(UIViewController *)self view]);
        sciLongPressedHighlightCell = cell;

        if (cell) {
            Ivar actIvar = class_getInstanceVariable([vc class], "_actions");
            NSArray *actions = actIvar ? object_getIvar(vc, actIvar) : nil;
            if (actions && actions.count >= 2 && actions.count <= 6) {
                Class actionCls = NSClassFromString(@"IGActionSheetControllerAction");
                if (actionCls) {
                    void (^handler)(void) = ^{
                        UIImage *cover = sciCoverImageFromCell(sciLongPressedHighlightCell);
                        sciViewCoverImage(cover);
                    };

                    SEL initSel = @selector(initWithTitle:subtitle:style:handler:accessibilityIdentifier:accessibilityLabel:);
                    typedef id (*InitFn)(id, SEL, id, id, NSInteger, id, id, id);
                    id newAction = ((InitFn)objc_msgSend)([actionCls alloc], initSel,
                        @"View cover", nil, 0, handler, nil, nil);

                    if (newAction) {
                        NSMutableArray *newActions = [actions mutableCopy];
                        [newActions addObject:newAction];
                        object_setIvar(vc, actIvar, [newActions copy]);
                    }
                }
            }
        }
    }

    orig_present(self, _cmd, vc, animated, completion);
}

__attribute__((constructor)) static void _highlightInit(void) {
    MSHookMessageEx([UIViewController class], @selector(presentViewController:animated:completion:),
                    (IMP)new_present, (IMP *)&orig_present);
}
