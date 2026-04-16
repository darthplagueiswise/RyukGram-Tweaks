// Disable feed refresh — background refresh and home tab refresh.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <substrate.h>

static BOOL sciDisableBgRefresh(void) {
    return [SCIUtils getBoolPref:@"disable_bg_refresh"];
}

static BOOL sciDisableHomeRefresh(void) {
    return [SCIUtils getBoolPref:@"disable_home_refresh"];
}

static BOOL sciDisableHomeScroll(void) {
    return [SCIUtils getBoolPref:@"disable_home_scroll"];
}

static BOOL sciDisableReelsRefresh(void) {
    return [SCIUtils getBoolPref:@"disable_reels_tab_refresh"];
}

// Returns 999999s when disabled (effectively never), -1 to keep IG's value.
static double sciOverrideInterval(void) {
    if (sciDisableBgRefresh()) return 999999;
    return -1;
}

// MARK: - Refresh-utility class-method overrides
// IGMainFeedRefreshUtility recomputes the intervals at runtime, ignoring the
// init args on IGMainFeedNetworkSource — override the 4 class methods too.

static double (*orig_wsRefresh)(id, SEL, id, id);
static double new_wsRefresh(id self, SEL _cmd, id ls, id store) {
    double o = sciOverrideInterval();
    return o > 0 ? o : orig_wsRefresh(self, _cmd, ls, store);
}

static double (*orig_wsBgRefresh)(id, SEL, id, id);
static double new_wsBgRefresh(id self, SEL _cmd, id ls, id store) {
    double o = sciOverrideInterval();
    return o > 0 ? o : orig_wsBgRefresh(self, _cmd, ls, store);
}

static double (*orig_peakWsRefresh)(id, SEL, double, id, id);
static double new_peakWsRefresh(id self, SEL _cmd, double iv, id ls, id store) {
    double o = sciOverrideInterval();
    return o > 0 ? o : orig_peakWsRefresh(self, _cmd, iv, ls, store);
}

static double (*orig_peakWsBgRefresh)(id, SEL, id, id);
static double new_peakWsBgRefresh(id self, SEL _cmd, id ls, id store) {
    double o = sciOverrideInterval();
    return o > 0 ? o : orig_peakWsBgRefresh(self, _cmd, ls, store);
}

%ctor {
    Class c = NSClassFromString(@"IGMainFeedViewModelUtility.IGMainFeedRefreshUtility");
    if (!c) return;
    Class meta = object_getClass(c);

    SEL s1 = NSSelectorFromString(@"warmStartRefreshIntervalWithLauncherSet:feedRefreshInstructionsStore:");
    if (class_getInstanceMethod(meta, s1))
        MSHookMessageEx(meta, s1, (IMP)new_wsRefresh, (IMP *)&orig_wsRefresh);

    SEL s2 = NSSelectorFromString(@"warmStartBackgroundRefreshIntervalWithLauncherSet:feedRefreshInstructionsStore:");
    if (class_getInstanceMethod(meta, s2))
        MSHookMessageEx(meta, s2, (IMP)new_wsBgRefresh, (IMP *)&orig_wsBgRefresh);

    SEL s3 = NSSelectorFromString(@"onPeakWarmStartRefreshIntervalWithWarmStartFetchInterval:launcherSet:feedRefreshInstructionsStore:");
    if (class_getInstanceMethod(meta, s3))
        MSHookMessageEx(meta, s3, (IMP)new_peakWsRefresh, (IMP *)&orig_peakWsRefresh);

    SEL s4 = NSSelectorFromString(@"onPeakWarmStartBackgroundRefreshIntervalWithLauncherSet:feedRefreshInstructionsStore:");
    if (class_getInstanceMethod(meta, s4))
        MSHookMessageEx(meta, s4, (IMP)new_peakWsBgRefresh, (IMP *)&orig_peakWsBgRefresh);
}

// MARK: - Background refresh

%hook IGMainFeedNetworkSource

- (instancetype)initWithDeps:(id)a1
                       posts:(id)a2
                   nextMaxID:(id)a3
     initialPaginationSource:(id)a4
        contentCoordinator:(id)a5
dataSourceSupplementaryItemsProvider:(id)a6
     disableAutomaticRefresh:(BOOL)disable
       disableSerialization:(BOOL)a8
                   sessionId:(id)a9
             analyticsModule:(id)a10
       serializationSuffix:(id)a11
         disableFlashFeedTLI:(BOOL)a12
  disableFlashFeedOnColdStart:(BOOL)a13
    disableResponseDeferral:(BOOL)a14
             hidesStoriesTray:(BOOL)a15
             isSecondaryFeed:(BOOL)a16
collectionViewBackgroundColorOverride:(id)a17
       minWarmStartFetchInterval:(double)a18
  peakMinWarmStartFetchInterval:(double)a19
minimumWarmStartBackgroundedInterval:(double)a20
peakMinimumWarmStartBackgroundedInterval:(double)a21
supplementalFeedHoistedMediaID:(id)a22
          headerTitleOverride:(id)a23
             isInFollowingTab:(BOOL)a24
useShimmerLoadingWhenNoStoriesTray:(BOOL)a25 {

    double override = sciOverrideInterval();
    if (sciDisableBgRefresh()) disable = YES;
    if (override > 0) { a18 = override; a19 = override; a20 = override; a21 = override; }

    return %orig(a1, a2, a3, a4, a5, a6, disable, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25);
}

// Getter overrides for instances created before the class hooks landed.
- (double)minWarmStartFetchInterval {
    double o = sciOverrideInterval();
    return o > 0 ? o : %orig;
}
- (double)peakMinWarmStartFetchInterval {
    double o = sciOverrideInterval();
    return o > 0 ? o : %orig;
}
- (double)minimumWarmStartBackgroundedInterval {
    double o = sciOverrideInterval();
    return o > 0 ? o : %orig;
}
- (double)peakMinimumWarmStartBackgroundedInterval {
    double o = sciOverrideInterval();
    return o > 0 ? o : %orig;
}

%end

// MARK: - Hot start refresh

%hook IGMainFeedViewController

- (void)hotStartRefresh {
    if (sciDisableBgRefresh()) return;
    %orig;
}

%end

// MARK: - Home tab refresh

%hook IGTabBarController

- (void)_timelineButtonPressed {
    BOOL noRefresh = sciDisableHomeRefresh();
    BOOL noScroll = sciDisableHomeScroll();

    if (!noRefresh && !noScroll) { %orig; return; }

    UIViewController *selected = nil;
    if ([self respondsToSelector:@selector(selectedViewController)])
        selected = [self valueForKey:@"selectedViewController"];

    BOOL onFeedTab = NO;
    if (selected) {
        UIViewController *top = [selected isKindOfClass:[UINavigationController class]]
            ? [(UINavigationController *)selected topViewController] : selected;
        onFeedTab = [NSStringFromClass([top class]) containsString:@"MainFeed"];
    }

    if (!onFeedTab) { %orig; return; }
    if (noScroll) return;

    // noRefresh only — scroll to top without refreshing.
    UIViewController *top = [selected isKindOfClass:[UINavigationController class]]
        ? [(UINavigationController *)selected topViewController] : selected;

    NSMutableArray *queue = [NSMutableArray arrayWithObject:top.view];
    int scanned = 0;
    while (queue.count && scanned < 30) {
        UIView *cur = queue.firstObject; [queue removeObjectAtIndex:0]; scanned++;
        if ([cur isKindOfClass:[UICollectionView class]]) {
            UIScrollView *sv = (UIScrollView *)cur;
            [sv setContentOffset:CGPointMake(0, -sv.adjustedContentInset.top) animated:YES];
            return;
        }
        for (UIView *s in cur.subviews) [queue addObject:s];
    }
}

// MARK: - Reels tab refresh

- (void)_discoverVideoButtonPressed {
    if (!sciDisableReelsRefresh()) { %orig; return; }

    UIViewController *selected = nil;
    if ([self respondsToSelector:@selector(selectedViewController)])
        selected = [self valueForKey:@"selectedViewController"];

    BOOL onReelsTab = NO;
    if (selected) {
        UIViewController *top = [selected isKindOfClass:[UINavigationController class]]
            ? [(UINavigationController *)selected topViewController] : selected;
        NSString *cls = NSStringFromClass([top class]);
        onReelsTab = [cls containsString:@"Sundial"] || [cls containsString:@"Reels"]
                  || [cls containsString:@"DiscoverVideo"];
    }

    if (!onReelsTab) { %orig; return; }
}

%end
