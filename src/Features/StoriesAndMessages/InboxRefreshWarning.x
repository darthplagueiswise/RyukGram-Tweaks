// Pull-to-refresh in the DMs tab silently clears preserved (locally retained)
// unsent messages. This hook intercepts _pullToRefreshIfPossible to show a
// confirmation dialog when both keep_deleted_message and
// warn_refresh_clears_preserved are on.
#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

extern NSMutableSet *sciGetPreservedIds(void);
extern void sciClearPreservedIds(void);

static BOOL sciRefreshConfirmInFlight = NO;
static BOOL sciRefreshAlertVisible = NO;

static UIRefreshControl *sciFindRefreshControl(UIViewController *vc) {
    Class igRC = NSClassFromString(@"IGRefreshControl");
    NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
    while (stack.count > 0) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ((igRC && [v isKindOfClass:igRC]) || [v isKindOfClass:[UIRefreshControl class]]) {
            return (UIRefreshControl *)v;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return nil;
}

// On cancel, the IGRefreshControl's state machine is already idle by the time
// our handler runs — but the scroll view's contentInset stays expanded, leaving
// the spinner area visually exposed. We grab the idle inset via the inbox VC's
// idleTopContentInsetForRefreshControl: helper and animate the inset back.
static void sciCancelRefresh(UIViewController *vc) {
    UIRefreshControl *rc = sciFindRefreshControl(vc);
    if (!rc) return;

    Ivar stateIvar = class_getInstanceVariable([rc class], "_refreshState");
    if (stateIvar) {
        ptrdiff_t off = ivar_getOffset(stateIvar);
        *(NSInteger *)((char *)(__bridge void *)rc + off) = 0;
    }
    Ivar animIvar = class_getInstanceVariable([rc class], "_swiftAnimationInfo");
    if (animIvar) object_setIvar(rc, animIvar, nil);
    if ([rc respondsToSelector:@selector(endRefreshing)]) [rc endRefreshing];

    SEL didEnd = NSSelectorFromString(@"refreshControlDidEndFinishLoadingAnimation:");
    if ([vc respondsToSelector:didEnd]) {
        ((void(*)(id, SEL, id))objc_msgSend)(vc, didEnd, rc);
    }

    UIScrollView *scroll = nil;
    UIView *cur = rc.superview;
    while (cur) {
        if ([cur isKindOfClass:[UIScrollView class]]) { scroll = (UIScrollView *)cur; break; }
        cur = cur.superview;
    }
    if (scroll) {
        SEL idleSel = NSSelectorFromString(@"idleTopContentInsetForRefreshControl:");
        CGFloat idleInset = scroll.contentInset.top;
        if ([vc respondsToSelector:idleSel]) {
            idleInset = ((CGFloat(*)(id, SEL, id))objc_msgSend)(vc, idleSel, rc);
        }
        UIEdgeInsets insets = scroll.contentInset;
        insets.top = idleInset;
        [UIView animateWithDuration:0.25 animations:^{
            scroll.contentInset = insets;
            CGPoint o = scroll.contentOffset;
            if (o.y < -idleInset) o.y = -idleInset;
            scroll.contentOffset = o;
        }];
    }
}

static void (*orig_pullToRefresh)(id self, SEL _cmd);
static void new_pullToRefresh(id self, SEL _cmd) {
    if (sciRefreshConfirmInFlight ||
        ![SCIUtils getBoolPref:@"keep_deleted_message"] ||
        ![SCIUtils getBoolPref:@"warn_refresh_clears_preserved"]) {
        orig_pullToRefresh(self, _cmd);
        return;
    }

    // IG fires _pullToRefreshIfPossible repeatedly while the user holds the
    // pull gesture — drop re-entrant calls until the alert is dismissed.
    if (sciRefreshAlertVisible) return;

    NSUInteger count = sciGetPreservedIds().count;
    if (count == 0) {
        orig_pullToRefresh(self, _cmd);
        return;
    }

    UIViewController *vc = (UIViewController *)self;
    NSString *msg = [NSString stringWithFormat:
        @"Refreshing the DMs tab will clear %lu preserved unsent message%@. This cannot be undone.",
        (unsigned long)count, count == 1 ? @"" : @"s"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SCILocalized(@"Clear preserved messages?")
                                                                  message:msg
                                                           preferredStyle:UIAlertControllerStyleAlert];

    __weak UIViewController *weakSelf = vc;
    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Cancel") style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *a) {
        sciCancelRefresh(weakSelf);
        sciRefreshAlertVisible = NO;
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:SCILocalized(@"Refresh") style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        sciRefreshAlertVisible = NO;
        id strongSelf = weakSelf;
        if (!strongSelf) return;
        sciClearPreservedIds();
        sciRefreshConfirmInFlight = YES;
        ((void(*)(id, SEL))objc_msgSend)(strongSelf, _cmd);
        sciRefreshConfirmInFlight = NO;
    }]];

    sciRefreshAlertVisible = YES;
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:alert animated:YES completion:nil];
}

%ctor {
    Class cls = NSClassFromString(@"IGDirectInboxViewController");
    if (!cls) return;
    SEL sel = NSSelectorFromString(@"_pullToRefreshIfPossible");
    if (class_getInstanceMethod(cls, sel))
        MSHookMessageEx(cls, sel, (IMP)new_pullToRefresh, (IMP *)&orig_pullToRefresh);
}
