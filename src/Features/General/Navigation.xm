#import "../../Utils.h"

BOOL isSurfaceShown(IGMainAppSurfaceIntent *surface) {
    BOOL isShown = YES;

    // Feed
    if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"FEED"] && [SCIUtils getBoolPref:@"hide_feed_tab"]) {
        isShown = NO;
    }
    
    // Reels
    else if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"CLIPS"] && [SCIUtils getBoolPref:@"hide_reels_tab"]) {
        isShown = NO;
    }

    // Messages
    else if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"DIRECT"] && [SCIUtils getBoolPref:@"hide_messages_tab"]) {
        isShown = NO;
    }

    // Explore
    else if ([[surface tabStringFromSurfaceIntent] isEqualToString:@"SEARCH"] && [SCIUtils getBoolPref:@"hide_explore_tab"]) {
        isShown = NO;
    }

    // Create
    else if ([(NSNumber *)[surface valueForKey:@"_subtype"] unsignedIntegerValue] == 3 && [SCIUtils getBoolPref:@"hide_create_tab"]) {
        isShown = NO;
    }

    return isShown;
}

NSArray *filterSurfacesArray(NSArray *surfaces) {
    NSMutableArray *filteredSurfaces = [NSMutableArray array];

    for (IGMainAppSurfaceIntent *surface in surfaces) {
        if (![surface isKindOfClass:%c(IGMainAppSurfaceIntent)]) break;

        if (isSurfaceShown(surface)) {
            [filteredSurfaces addObject:surface];
        }
    }

    return filteredSurfaces;
}

///////////////////////////////////////////////

%hook IGTabBarControllerSwipeCoordinator
- (id)initWithSurfaces:(id)surfaces parentViewController:(id)controller enableHaptics:(_Bool)haptics launcherSet:(id)set {
    // Removes the surface from the main swipeable app collection view
    return %orig(filterSurfacesArray(surfaces), controller, haptics, set);
}
%end

%hook IGTabBarController
- (void)_layoutTabBar {
    // Prevents the wrong icon from being shown as selected because of mismatched surface array indexes
    NSArray *_tabBarSurfaces = [SCIUtils getIvarForObj:self name:"_tabBarSurfaces"];

    [SCIUtils setIvarForObj:self name:"_tabBarSurfaces" value:filterSurfacesArray(_tabBarSurfaces)];
    
    %orig;
}

- (id)_buttonForTabBarSurface:(id)surface {
    // Prevents the button from being added to the tab bar 
    id button = %orig(surface);

    if (!isSurfaceShown(surface)) {
        return nil;
    }

    return button;
}
%end

// Demangled name: IGNavConfiguration.IGNavConfiguration
%hook _TtC18IGNavConfiguration18IGNavConfiguration
- (NSInteger)tabOrdering {

    if ([[SCIUtils getStringPref:@"nav_icon_ordering"] isEqualToString:@"classic"]) return 0;
    else if ([[SCIUtils getStringPref:@"nav_icon_ordering"] isEqualToString:@"standard"]) return 1;
    else if ([[SCIUtils getStringPref:@"nav_icon_ordering"] isEqualToString:@"alternate"]) return 2;

    return %orig;

}
- (void)setTabOrdering:(NSInteger)arg1 {
    return;
}

- (BOOL)isHomecomingEnabled {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"]) return YES;
    if ([SCIUtils getBoolPref:@"igt_homecoming"]) return YES;
    return %orig;
}
- (void)setIsHomecomingEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)isHomecomingStoriesAccessFaceClusterEnabled {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"] || [SCIUtils getBoolPref:@"igt_homecoming"]) return YES;
    return %orig;
}
- (void)setIsHomecomingStoriesAccessFaceClusterEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)isHomecomingTapToPauseHiddenInPreview {
    if ([SCIUtils getBoolPref:@"liquid_glass_surfaces"] || [SCIUtils getBoolPref:@"igt_homecoming"]) return YES;
    return %orig;
}
- (void)setIsHomecomingTapToPauseHiddenInPreview:(BOOL)arg1 {
    return;
}
- (BOOL)isTabSwipingEnabled {
    // Swipe lands on stripped tabs in messages-only.
    if ([SCIUtils getBoolPref:@"messages_only"]) return NO;
    if ([[SCIUtils getStringPref:@"swipe_nav_tabs"] isEqualToString:@"enabled"]) return YES;
    else if ([[SCIUtils getStringPref:@"swipe_nav_tabs"] isEqualToString:@"disabled"]) return NO;
    return %orig;
}
- (void)setIsTabSwipingEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)isDynamicTabStoryGridEnabled {
    if ([SCIUtils getBoolPref:@"igt_dynamic_tab"]) return YES;
    return %orig;
}
- (void)setIsDynamicTabStoryGridEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)isDynamicTabFullscreenSwitcherEnabled {
    if ([SCIUtils getBoolPref:@"igt_dynamic_tab"]) return YES;
    return %orig;
}
- (void)setIsDynamicTabFullscreenSwitcherEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)isReelsSecondEnabled {
    if ([SCIUtils getBoolPref:@"igt_reels_first"]) return YES;
    return %orig;
}
- (void)setIsReelsSecondEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)audioRampingOnSwipeEnabled {
    if ([SCIUtils getBoolPref:@"igt_audio_ramping"]) return YES;
    return %orig;
}
- (void)setAudioRampingOnSwipeEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)isFeedCullingOnStatusBarEnabled {
    if ([SCIUtils getBoolPref:@"igt_feed_culling"]) return YES;
    return %orig;
}
- (void)setIsFeedCullingOnStatusBarEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)isFeedDedupFromReelsOptimizationEnabled {
    if ([SCIUtils getBoolPref:@"igt_feed_dedup"]) return YES;
    return %orig;
}
- (void)setIsFeedDedupFromReelsOptimizationEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)isFriendsFeedSeeOlderPostsEnabled {
    if ([SCIUtils getBoolPref:@"igt_friends_feed"]) return YES;
    return %orig;
}
- (void)setIsFriendsFeedSeeOlderPostsEnabled:(BOOL)arg1 {
    return;
}
- (BOOL)enablePullToCarrera {
    if ([SCIUtils getBoolPref:@"igt_pull_to_carrera"]) return YES;
    return %orig;
}
- (void)setEnablePullToCarrera:(BOOL)arg1 {
    return;
}
%end

%hook IGHomeFeedHeaderView
- (void)didMoveToWindow {
    %orig;

    if ([SCIUtils getBoolPref:@"hide_messages_tab"]) {
        UIButton *rightButton = [self valueForKey:@"rightButton"];
        if (rightButton) {
            NSLog(@"[SCInsta] Hiding messages tab (on feed)");

            [rightButton removeFromSuperview];
        }
    }
}
<<<<<<< HEAD
%end
=======
%end
>>>>>>> bef1fcf (Update merged RyukGram project)
