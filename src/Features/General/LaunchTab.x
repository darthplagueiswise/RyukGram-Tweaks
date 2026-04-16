// Force launch into a chosen tab. Ignored while messages_only is active.

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/message.h>

static NSString *sciSelectorForLaunchPref(NSString *p) {
    if ([p isEqualToString:@"feed"])    return @"_timelineButtonPressed";
    if ([p isEqualToString:@"explore"]) return @"_exploreButtonPressed";
    if ([p isEqualToString:@"reels"])   return @"_discoverVideoButtonPressed";
    if ([p isEqualToString:@"inbox"])   return @"_directInboxButtonPressed";
    if ([p isEqualToString:@"profile"]) return @"_profileButtonPressed";
    return nil;
}

%hook IGTabBarController
- (void)viewWillAppear:(BOOL)animated {
    if (![SCIUtils getBoolPref:@"messages_only"]) {
        static BOOL fired = NO;
        if (!fired) {
            fired = YES;
            NSString *pref = [SCIUtils getStringPref:@"launch_tab"];
            NSString *selName = sciSelectorForLaunchPref(pref);
            if (selName) {
                SEL s = NSSelectorFromString(selName);
                if ([self respondsToSelector:s])
                    ((void(*)(id, SEL))objc_msgSend)(self, s);
            }
        }
    }
    %orig;
}
%end
