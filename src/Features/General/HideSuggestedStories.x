// Hide suggested stories from the tray. Drops items the user doesn't follow
// (friendship_status.following=0 or empty fieldCache); highlights pass through.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

// IGListAdapter declared in InstagramHeaders.h

static __weak id sciTrayAdapter = nil;

// ── Suggested item detection ──

// Returns YES if the item should be kept. Highlights / non-tray rows pass
// through; followed reels keep; empty fieldCache (freshly-streamed suggested
// users) drops; otherwise check friendship_status.following.
static BOOL sciIsFollowedTrayItem(id obj) {
    if (![NSStringFromClass([obj class]) isEqualToString:@"IGStoryTrayViewModel"]) return YES;

    @try {
        if ([[obj valueForKey:@"isCurrentUserReel"] boolValue]) return YES;

        id owner = [obj valueForKey:@"reelOwner"];
        if (!owner) return YES;

        Ivar userIvar = class_getInstanceVariable([owner class], "_userReelOwner_user");
        if (!userIvar) return YES;
        id igUser = object_getIvar(owner, userIvar);
        if (!igUser) return YES;

        Ivar fcIvar = NULL;
        for (Class c = [igUser class]; c && !fcIvar; c = class_getSuperclass(c))
            fcIvar = class_getInstanceVariable(c, "_fieldCache");
        if (!fcIvar) return YES;

        const char *fcType = ivar_getTypeEncoding(fcIvar);
        if (!fcType || fcType[0] != '@') return YES;

        id fc = object_getIvar(igUser, fcIvar);
        if (![fc isKindOfClass:[NSDictionary class]]) return YES;
        if ([(NSDictionary *)fc count] == 0) return NO;

        id fs = [(NSDictionary *)fc objectForKey:@"friendship_status"];
        if (!fs) return YES;

        return [[fs valueForKey:@"following"] boolValue];
    } @catch (__unused NSException *e) {
        return YES;
    }
}

// ── Data source filter ──

static NSArray *(*orig_objectsForListAdapter)(id, SEL, id);
static NSArray *hook_objectsForListAdapter(id self, SEL _cmd, id adapter) {
    NSArray *objects = orig_objectsForListAdapter(self, _cmd, adapter);
    sciTrayAdapter = adapter;

    if (![SCIUtils getBoolPref:@"hide_suggested_stories"]) return objects;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:objects.count];
    for (id obj in objects) {
        if (sciIsFollowedTrayItem(obj)) [filtered addObject:obj];
    }
    return [filtered copy];
}

// ── Reload tray on pref change ──

static void sciReloadTray(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        IGListAdapter *adapter = sciTrayAdapter;
        if (adapter) [adapter performUpdatesAnimated:YES completion:nil];
    });
}

%ctor {
    Class dsCls = NSClassFromString(@"IGStoryTrayListAdapterDataSource");
    if (!dsCls) return;

    SEL sel = NSSelectorFromString(@"objectsForListAdapter:");
    if (class_getInstanceMethod(dsCls, sel))
        MSHookMessageEx(dsCls, sel, (IMP)hook_objectsForListAdapter, (IMP *)&orig_objectsForListAdapter);

    [[NSNotificationCenter defaultCenter] addObserverForName:@"SCISuggestedStoriesReload"
                                                      object:nil queue:nil
                                                  usingBlock:^(NSNotification *n) { sciReloadTray(); }];
}
