// Messages-only mode — no-op the tab creators we don't want, force inbox at launch.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL sciMsgOnly(void) { return [SCIUtils getBoolPref:@"messages_only"]; }

%hook IGTabBarController

// Block tab creation entirely so they never enter the buttons array (no gaps).
- (void)_createAndConfigureTimelineButtonIfNeeded   { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureReelsButtonIfNeeded      { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureExploreButtonIfNeeded    { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureCameraButtonIfNeeded     { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureDynamicTabButtonIfNeeded { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureNewsButtonIfNeeded       { if (sciMsgOnly()) return; %orig; }
- (void)_createAndConfigureStreamsButtonIfNeeded    { if (sciMsgOnly()) return; %orig; }

// Force initial selection to inbox once after the tab bar has fully laid out.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static BOOL launched = NO;
    if (sciMsgOnly() && !launched) {
        launched = YES;
        SEL s = NSSelectorFromString(@"_directInboxButtonPressed");
        if ([self respondsToSelector:s])
            ((void(*)(id, SEL))objc_msgSend)(self, s);
    }
}

// Surface enum no longer maps cleanly to the trimmed _buttons array, so flip
// the selected state ourselves and nudge the liquid-glass indicator.
%new - (void)sciSyncTabBarSelection:(NSString *)which {
    Class c = [self class];
    Ivar ibIv = class_getInstanceVariable(c, "_directInboxButton");
    Ivar pbIv = class_getInstanceVariable(c, "_profileButton");
    UIButton *inbox = ibIv ? object_getIvar(self, ibIv) : nil;
    UIButton *profile = pbIv ? object_getIvar(self, pbIv) : nil;
    BOOL profileActive = [which isEqualToString:@"profile"];
    if ([inbox respondsToSelector:@selector(setSelected:)]) inbox.selected = !profileActive;
    if ([profile respondsToSelector:@selector(setSelected:)]) profile.selected = profileActive;

    // No-op on classic tab bar (selector only exists on IGLiquidGlassInteractiveTabBar).
    Ivar tbIv = class_getInstanceVariable(c, "_tabBar");
    id tabBar = tbIv ? object_getIvar(self, tbIv) : nil;
    NSInteger idx = profileActive ? 1 : 0;
    SEL setIdx = NSSelectorFromString(@"setSelectedTabBarItemIndex:animateIndicator:");
    if ([tabBar respondsToSelector:setIdx])
        ((void(*)(id, SEL, NSInteger, BOOL))objc_msgSend)(tabBar, setIdx, idx, YES);
}

- (void)_directInboxButtonPressed {
    %orig;
    if (sciMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), @"inbox");
}
- (void)_profileButtonPressed {
    %orig;
    if (sciMsgOnly())
        ((void(*)(id, SEL, id))objc_msgSend)(self, @selector(sciSyncTabBarSelection:), @"profile");
}

%end
