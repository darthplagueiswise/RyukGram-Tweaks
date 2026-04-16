// Mark seen + advance when replying or reacting to a story.

#import "../../Utils.h"
#import "StoryHelpers.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

extern __weak UIViewController *sciActiveStoryVC;
extern BOOL sciAdvanceBypassActive;

static UIView *sciFindOverlayForStoryVC(UIViewController *vc) {
    if (!vc) return nil;
    Class overlayCls = NSClassFromString(@"IGStoryFullscreenOverlayView");
    if (!overlayCls) return nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:overlayCls]) return v;
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return nil;
}

static void sciMarkSeenOnReply(void) {
    if (![SCIUtils getBoolPref:@"seen_on_story_reply"]) return;
    UIView *overlay = sciFindOverlayForStoryVC(sciActiveStoryVC);
    if (!overlay) return;
    SEL sel = @selector(sciMarkSeenTapped:);
    if ([overlay respondsToSelector:sel])
        ((void(*)(id, SEL, id))objc_msgSend)(overlay, sel, nil);
}

static uint64_t sciLastReplyAdvanceTime = 0;

static void sciAdvanceOnReply(void) {
    if (![SCIUtils getBoolPref:@"advance_on_story_reply"]) return;
    UIViewController *storyVC = sciActiveStoryVC;
    if (!storyVC) return;
    id sectionCtrl = sciFindSectionController(storyVC);
    if (!sectionCtrl) return;

    // Dedup across multiple hooks firing for the same event
    uint64_t now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
    if (now - sciLastReplyAdvanceTime < 500000000ULL) return;
    sciLastReplyAdvanceTime = now;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sciAdvanceBypassActive = YES;
        SEL advSel = NSSelectorFromString(@"advanceToNextItemWithNavigationAction:");
        if ([sectionCtrl respondsToSelector:advSel])
            ((void(*)(id, SEL, NSInteger))objc_msgSend)(sectionCtrl, advSel, 1);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            id sc2 = storyVC ? sciFindSectionController(storyVC) : nil;
            if (sc2) {
                SEL resumeSel = NSSelectorFromString(@"tryResumePlaybackWithReason:");
                if ([sc2 respondsToSelector:resumeSel])
                    ((void(*)(id, SEL, NSInteger))objc_msgSend)(sc2, resumeSel, 0);
            }
            sciAdvanceBypassActive = NO;
        });
    });
}

static void sciOnStoryReply(void) {
    sciMarkSeenOnReply();
    sciAdvanceOnReply();
}

// Text reply — IGDirectComposer is shared with DMs, gate by active story VC.
%hook IGDirectComposer
- (void)_didTapSend:(id)arg {
    %orig;
    if (sciActiveStoryVC) sciOnStoryReply();
}
- (void)_send {
    %orig;
    if (sciActiveStoryVC) sciOnStoryReply();
}
%end

// Composer emoji reaction buttons (forwarded to the Swift footer delegate)
static void (*orig_footerEmojiQuick)(id, SEL, id, id);
static void new_footerEmojiQuick(id self, SEL _cmd, id inputView, id btn) {
    orig_footerEmojiQuick(self, _cmd, inputView, btn);
    sciOnStoryReply();
}

static void (*orig_footerEmojiReaction)(id, SEL, id, id);
static void new_footerEmojiReaction(id self, SEL _cmd, id inputView, id btn) {
    orig_footerEmojiReaction(self, _cmd, inputView, btn);
    sciOnStoryReply();
}

// Swipe-up quick reactions tray
static void (*orig_qrCtrlDidTapEmoji)(id, SEL, id, id, id);
static void new_qrCtrlDidTapEmoji(id self, SEL _cmd, id view, id sourceBtn, id emoji) {
    orig_qrCtrlDidTapEmoji(self, _cmd, view, sourceBtn, emoji);
    sciOnStoryReply();
}

static void (*orig_qrDelegateDidTapEmoji)(id, SEL, id, id, id);
static void new_qrDelegateDidTapEmoji(id self, SEL _cmd, id ctrl, id sourceBtn, id emoji) {
    orig_qrDelegateDidTapEmoji(self, _cmd, ctrl, sourceBtn, emoji);
    sciOnStoryReply();
}

// Swift classes aren't guaranteed to be registered at %ctor time — install
// lazily on first overlay appearance as a fallback.
static void sciInstallReplyHooks(void) {
    static BOOL installed = NO;
    if (installed) return;

    Class footerCls  = NSClassFromString(@"IGStoryDefaultFooter.IGStoryFullscreenDefaultFooterView");
    Class qrCtrl     = NSClassFromString(@"IGStoryQuickReactions.IGStoryQuickReactionsController");
    Class qrDelegate = NSClassFromString(@"IGStoryQuickReactionsDelegate.IGStoryQuickReactionsDelegateImpl");
    if (!footerCls || !qrCtrl || !qrDelegate) return;
    installed = YES;

    SEL quick = NSSelectorFromString(@"inputView:didTapEmojiQuickReactionButton:");
    if (class_getInstanceMethod(footerCls, quick))
        MSHookMessageEx(footerCls, quick, (IMP)new_footerEmojiQuick, (IMP *)&orig_footerEmojiQuick);

    SEL reaction = NSSelectorFromString(@"inputView:didTapEmojiReactionButton:");
    if (class_getInstanceMethod(footerCls, reaction))
        MSHookMessageEx(footerCls, reaction, (IMP)new_footerEmojiReaction, (IMP *)&orig_footerEmojiReaction);

    SEL qrSel = NSSelectorFromString(@"quickReactionsView:sourceEmojiButton:didTapEmoji:");
    if (class_getInstanceMethod(qrCtrl, qrSel))
        MSHookMessageEx(qrCtrl, qrSel, (IMP)new_qrCtrlDidTapEmoji, (IMP *)&orig_qrCtrlDidTapEmoji);

    SEL qrdSel = NSSelectorFromString(@"storyQuickReactionsController:sourceEmojiButton:didTapEmoji:");
    if (class_getInstanceMethod(qrDelegate, qrdSel))
        MSHookMessageEx(qrDelegate, qrdSel, (IMP)new_qrDelegateDidTapEmoji, (IMP *)&orig_qrDelegateDidTapEmoji);
}

%hook IGStoryFullscreenOverlayView
- (void)didMoveToWindow {
    %orig;
    sciInstallReplyHooks();
}
%end

%ctor {
    sciInstallReplyHooks();
}
