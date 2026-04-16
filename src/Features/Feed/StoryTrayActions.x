// Story tray long-press actions — adds "View profile picture" to the action sheet.
// Fetches HD profile pic via /api/v1/users/{pk}/info/.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../ActionButton/SCIMediaViewer.h"
#import "../../Networking/SCIInstagramAPI.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

static __weak id sciLongPressedTrayCell = nil;

// ── Helpers ──

static UIImage *sciProfileImageFromCell(id cell) {
    Ivar avIvar = class_getInstanceVariable([cell class], "_avatarView");
    if (!avIvar) return nil;
    UIView *avatarView = object_getIvar(cell, avIvar);
    if (!avatarView) return nil;
    Ivar imgIvar = class_getInstanceVariable([avatarView class], "_ownerImageView");
    if (!imgIvar) return nil;
    UIImageView *imgView = object_getIvar(avatarView, imgIvar);
    if ([imgView isKindOfClass:[UIImageView class]]) return imgView.image;
    return nil;
}

static NSString *sciUsernameFromCell(id cell) {
    @try {
        Ivar mi = class_getInstanceVariable([cell class], "_model");
        if (!mi) return nil;
        id model = object_getIvar(cell, mi);
        id title = [model valueForKey:@"title"];
        if ([title isKindOfClass:[NSAttributedString class]])
            return [[(NSAttributedString *)title string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    } @catch (NSException *e) {}
    return nil;
}

static NSString *sciFullNameFromCell(id cell) {
    @try {
        Ivar mi = class_getInstanceVariable([cell class], "_model");
        if (!mi) return nil;
        id model = object_getIvar(cell, mi);
        id owner = [model valueForKey:@"reelOwner"];
        if (!owner) return nil;
        Ivar ui = class_getInstanceVariable([owner class], "_userReelOwner_user");
        if (!ui) return nil;
        id igUser = object_getIvar(owner, ui);
        Ivar fi = NULL;
        for (Class c = [igUser class]; c && !fi; c = class_getSuperclass(c))
            fi = class_getInstanceVariable(c, "_fieldCache");
        if (!fi) return nil;
        id fc = object_getIvar(igUser, fi);
        if (![fc isKindOfClass:[NSDictionary class]]) return nil;
        id name = [(NSDictionary *)fc objectForKey:@"full_name"];
        if ([name isKindOfClass:[NSString class]] && [(NSString *)name length] > 0) return name;
    } @catch (NSException *e) {}
    return nil;
}

static NSString *sciCaptionFromCell(id cell) {
    NSString *username = sciUsernameFromCell(cell);
    NSString *fullName = sciFullNameFromCell(cell);
    if (username && fullName) return [NSString stringWithFormat:@"%@\n%@", username, fullName];
    return username ?: fullName;
}

static NSString *sciUserPKFromCell(id cell) {
    @try {
        Ivar mi = class_getInstanceVariable([cell class], "_model");
        if (!mi) return nil;
        id model = object_getIvar(cell, mi);
        id owner = [model valueForKey:@"reelOwner"];
        if (!owner) return nil;
        Ivar ui = class_getInstanceVariable([owner class], "_userReelOwner_user");
        if (!ui) return nil;
        id igUser = object_getIvar(owner, ui);
        Ivar pi = NULL;
        for (Class c = [igUser class]; c && !pi; c = class_getSuperclass(c))
            pi = class_getInstanceVariable(c, "_pk");
        if (!pi) return nil;
        return [object_getIvar(igUser, pi) description];
    } @catch (NSException *e) {}
    return nil;
}

// Fetch HD profile pic via API, fallback to local avatar
static void sciShowHDProfilePic(NSString *pk, NSString *caption, UIImage *fallback) {
    NSString *path = [NSString stringWithFormat:@"users/%@/info/", pk];
    [SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
        if (error || !response) {
            if (fallback) {
                NSData *d = UIImageJPEGRepresentation(fallback, 1.0);
                NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"pfp_%@.jpg", pk]];
                [d writeToFile:p atomically:YES];
                [SCIMediaViewer showWithVideoURL:nil photoURL:[NSURL fileURLWithPath:p] caption:caption];
            }
            return;
        }

        NSDictionary *user = response[@"user"];
        NSString *hdURL = nil;

        NSDictionary *hdInfo = user[@"hd_profile_pic_url_info"];
        if ([hdInfo isKindOfClass:[NSDictionary class]]) hdURL = hdInfo[@"url"];

        if (!hdURL) {
            NSArray *versions = user[@"hd_profile_pic_versions"];
            if ([versions isKindOfClass:[NSArray class]] && versions.count > 0)
                hdURL = [versions.lastObject objectForKey:@"url"];
        }

        if (!hdURL) hdURL = user[@"profile_pic_url"];

        if (hdURL) {
            [SCIMediaViewer showWithVideoURL:nil photoURL:[NSURL URLWithString:hdURL] caption:caption];
        } else if (fallback) {
            NSData *d = UIImageJPEGRepresentation(fallback, 1.0);
            NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"pfp_%@.jpg", pk]];
            [d writeToFile:p atomically:YES];
            [SCIMediaViewer showWithVideoURL:nil photoURL:[NSURL fileURLWithPath:p] caption:caption];
        }
    }];
}

// ── Capture long-pressed cell ──

static void (*orig_didLongPressCell)(id, SEL, UIGestureRecognizer *);
static void hook_didLongPressCell(id self, SEL _cmd, UIGestureRecognizer *gesture) {
    if (gesture.state == UIGestureRecognizerStateBegan)
        sciLongPressedTrayCell = gesture.view;
    orig_didLongPressCell(self, _cmd, gesture);
}

// ── Inject action into the sheet ──

static void (*orig_present)(id, SEL, id, BOOL, id);
static void hook_present(id self, SEL _cmd, id vc, BOOL animated, id completion) {
    if (sciLongPressedTrayCell && [SCIUtils getBoolPref:@"story_tray_actions"]) {
        Ivar actIvar = class_getInstanceVariable([vc class], "_actions");
        NSArray *actions = actIvar ? object_getIvar(vc, actIvar) : nil;

        if (actions) {
            id cell = sciLongPressedTrayCell;
            sciLongPressedTrayCell = nil;

            Class actionCls = NSClassFromString(@"IGActionSheetControllerAction");
            NSString *pk = sciUserPKFromCell(cell);
            if (actionCls && pk) {
                NSString *caption = sciCaptionFromCell(cell);
                UIImage *localPic = sciProfileImageFromCell(cell);

                typedef id (*InitFn)(id, SEL, id, id, NSInteger, id, id, id);
                void (^handler)(void) = ^{ sciShowHDProfilePic(pk, caption, localPic); };
                id action = ((InitFn)objc_msgSend)([actionCls alloc],
                    @selector(initWithTitle:subtitle:style:handler:accessibilityIdentifier:accessibilityLabel:),
                    @"View profile picture", nil, (NSInteger)0, handler, nil, nil);

                if (action) {
                    NSMutableArray *newActions = [actions mutableCopy];
                    [newActions insertObject:action atIndex:0];
                    object_setIvar(vc, actIvar, [newActions copy]);
                }
            }
        }
    }

    if (sciLongPressedTrayCell) sciLongPressedTrayCell = nil;
    orig_present(self, _cmd, vc, animated, completion);
}

%ctor {
    Class scCls = NSClassFromString(@"IGStorySectionController");
    if (scCls) {
        SEL sel = NSSelectorFromString(@"_didLongPressCell:");
        if (class_getInstanceMethod(scCls, sel))
            MSHookMessageEx(scCls, sel, (IMP)hook_didLongPressCell, (IMP *)&orig_didLongPressCell);
    }

    MSHookMessageEx([UIViewController class], @selector(presentViewController:animated:completion:),
                    (IMP)hook_present, (IMP *)&orig_present);
}
