// Full last active — replaces "Active Xm ago" with full date in DM chats.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSDateFormatter *sciDMDateFormatter(void) {
    static NSDateFormatter *df = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"MMM d 'at' h:mm a";
    });
    return df;
}

// Replace "Active Xm/h ago" with full date using _lastActiveDate from the thread
static void sciUpdateSubtitleLabel(UIView *titleView) {
    if (![SCIUtils getBoolPref:@"dm_full_last_active"]) return;

    // Get _subtitleLabel
    Ivar subIvar = class_getInstanceVariable([titleView class], "_subtitleLabel");
    if (!subIvar) return;
    UILabel *label = object_getIvar(titleView, subIvar);
    if (![label isKindOfClass:[UILabel class]]) return;

    NSString *text = label.text;
    if (!text.length) return;

    // Only replace "Active X ago" patterns, not "Active now" or "Typing..."
    if (![text hasPrefix:@"Active "] || ![text hasSuffix:@"ago"]) return;

    // Get the _titleViewModel to find lastActiveDate
    Ivar vmIvar = class_getInstanceVariable([titleView class], "_titleViewModel");
    if (!vmIvar) return;
    id vm = object_getIvar(titleView, vmIvar);
    if (!vm) return;

    // Try to get lastActiveDate from the view model
    NSDate *activeDate = nil;

    // Check vm for lastActiveDate / lastActive / activeDate
    for (NSString *sel in @[@"lastActiveDate", @"lastActive", @"activeDate"]) {
        if ([vm respondsToSelector:NSSelectorFromString(sel)]) {
            id val = [vm valueForKey:sel];
            if ([val isKindOfClass:[NSDate class]]) { activeDate = val; break; }
            if ([val isKindOfClass:[NSNumber class]]) {
                activeDate = [NSDate dateWithTimeIntervalSince1970:[(NSNumber *)val doubleValue]];
                break;
            }
        }
    }

    // If no date on VM, parse from the label text as fallback
    if (!activeDate) {
        // "Active 8m ago" → 8 minutes ago
        // "Active 2h ago" → 2 hours ago
        NSTimeInterval delta = 0;
        NSScanner *scanner = [NSScanner scannerWithString:text];
        [scanner scanString:@"Active " intoString:nil];
        double val = 0;
        if ([scanner scanDouble:&val]) {
            NSString *rest = [text substringFromIndex:scanner.scanLocation];
            if ([rest hasPrefix:@"m"]) delta = val * 60;
            else if ([rest hasPrefix:@"h"]) delta = val * 3600;
            else if ([rest hasPrefix:@"d"]) delta = val * 86400;
        }
        if (delta > 0) {
            activeDate = [NSDate dateWithTimeIntervalSinceNow:-delta];
        }
    }

    if (!activeDate) return;

    NSString *formatted = [sciDMDateFormatter() stringFromDate:activeDate];
    if (formatted.length) {
        label.text = formatted;

        // Also update _subtitleView and _transitionalSubtitleLabel if they exist
        Ivar svIvar = class_getInstanceVariable([titleView class], "_subtitleView");
        if (svIvar) {
            id sv = object_getIvar(titleView, svIvar);
            if ([sv isKindOfClass:[UILabel class]])
                [(UILabel *)sv setText:label.text];
        }
        Ivar tsIvar = class_getInstanceVariable([titleView class], "_transitionalSubtitleLabel");
        if (tsIvar) {
            id ts = object_getIvar(titleView, tsIvar);
            if ([ts isKindOfClass:[UILabel class]])
                [(UILabel *)ts setText:label.text];
        }
    }
}

%hook IGDirectLeftAlignedTitleView

- (void)setTitleViewModel:(id)vm {
    %orig;
    sciUpdateSubtitleLabel(self);
}

- (void)animationCoordinatorDidUpdate:(id)coordinator {
    %orig;
    sciUpdateSubtitleLabel(self);
}

%end
