// Follow indicator — shows whether the profile user follows you.
// Fetches via /api/v1/friendships/show/{pk}/, renders inside the stats container.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Networking/SCIInstagramAPI.h"
#import <objc/runtime.h>
#import <objc/message.h>

// IGProfileViewController declared in InstagramHeaders.h

static const NSInteger kFollowBadgeTag = 99788;

static NSString *sciPKFromUser(id igUser) {
    if (!igUser) return nil;
    Ivar pkIvar = NULL;
    for (Class c = [igUser class]; c && !pkIvar; c = class_getSuperclass(c))
        pkIvar = class_getInstanceVariable(c, "_pk");
    if (!pkIvar) return nil;
    return [object_getIvar(igUser, pkIvar) description];
}

static NSString *sciCurrentUserPK(void) {
    @try {
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in scene.windows) {
                id session = [window valueForKey:@"userSession"];
                if (!session) continue;
                id su = [session valueForKey:@"user"];
                if (su) return sciPKFromUser(su);
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

// Cache follow status on the VC to avoid re-fetching
static const char kFollowStatusKey;
static NSNumber *sciGetFollowStatus(id vc) {
    return objc_getAssociatedObject(vc, &kFollowStatusKey);
}
static void sciSetFollowStatus(id vc, NSNumber *status) {
    objc_setAssociatedObject(vc, &kFollowStatusKey, status, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void sciRenderBadge(UIViewController *vc) {
    NSNumber *status = sciGetFollowStatus(vc);
    if (!status) return;
    BOOL followedBy = [status boolValue];

    UIView *statContainer = nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:vc.view];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass([v class]) containsString:@"StatButtonContainerView"]) {
            statContainer = v;
            break;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    if (!statContainer) return;

    UIView *old = [statContainer viewWithTag:kFollowBadgeTag];
    if (old) [old removeFromSuperview];

    UILabel *badge = [[UILabel alloc] init];
    badge.tag = kFollowBadgeTag;
    badge.text = followedBy ? SCILocalized(@"Follows you") : SCILocalized(@"Doesn't follow you");
    badge.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    badge.textColor = followedBy
        ? [UIColor colorWithRed:0.3 green:0.75 blue:0.4 alpha:1.0]
        : [UIColor colorWithRed:0.85 green:0.3 blue:0.3 alpha:1.0];
    [badge sizeToFit];

    CGFloat x = 0;
    for (UIView *sub in statContainer.subviews) {
        if (!sub.isHidden && sub.frame.size.width > 0) {
            x = sub.frame.origin.x;
            break;
        }
    }

    badge.frame = CGRectMake(x, statContainer.bounds.size.height - badge.frame.size.height - 2,
                             badge.frame.size.width, badge.frame.size.height);
    [statContainer addSubview:badge];
}

%hook IGProfileViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (![SCIUtils getBoolPref:@"follow_indicator"]) return;

    // Already fetched — just re-render
    if (sciGetFollowStatus(self)) {
        sciRenderBadge(self);
        return;
    }

    id igUser = nil;
    @try { igUser = [self valueForKey:@"user"]; } @catch (NSException *e) {}
    if (!igUser) return;

    NSString *profilePK = sciPKFromUser(igUser);
    NSString *myPK = sciCurrentUserPK();
    if (!profilePK || !myPK || [profilePK isEqualToString:myPK]) return;

    __weak UIViewController *weakSelf = self;
    NSString *path = [NSString stringWithFormat:@"friendships/show/%@/", profilePK];
    [SCIInstagramAPI sendRequestWithMethod:@"GET" path:path body:nil completion:^(NSDictionary *response, NSError *error) {
        if (error || !response) return;
        BOOL followedBy = [response[@"followed_by"] boolValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *vc = weakSelf;
            if (!vc) return;
            sciSetFollowStatus(vc, @(followedBy));
            sciRenderBadge(vc);
        });
    }];
}

%end
