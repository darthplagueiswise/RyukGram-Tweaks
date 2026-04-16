// Date format hooks — replace IG's relative timestamps with a custom format.
// Each NSDate formatter selector is independently toggleable via prefs
// (date_fmt_<name>) so users can apply the format surface-by-surface.

#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "SCIDateFormatEntries.h"
#import <substrate.h>

static NSDictionary *sciDateFormats(BOOL sec) {
    return sec ? @{
        @"short":        @"MMM d",
        @"medium":       @"MMM d, yyyy",
        @"full":         @"MMM d, yyyy 'at' h:mm:ss a",
        @"time_12":      @"MMM d 'at' h:mm:ss a",
        @"time_24":      @"MMM d 'at' HH:mm:ss",
        @"dd_mmm":       @"dd-MMM-yyyy 'at' h:mm:ss a",
        @"day_slash":    @"dd/MM/yyyy h:mm:ss a",
        @"month_slash":  @"MM/dd/yyyy h:mm:ss a",
        @"euro":         @"dd.MM.yyyy HH:mm:ss",
        @"iso":          @"yyyy-MM-dd",
        @"iso_time":     @"yyyy-MM-dd HH:mm:ss",
    } : @{
        @"short":        @"MMM d",
        @"medium":       @"MMM d, yyyy",
        @"full":         @"MMM d, yyyy 'at' h:mm a",
        @"time_12":      @"MMM d 'at' h:mm a",
        @"time_24":      @"MMM d 'at' HH:mm",
        @"dd_mmm":       @"dd-MMM-yyyy 'at' h:mm a",
        @"day_slash":    @"dd/MM/yyyy h:mm a",
        @"month_slash":  @"MM/dd/yyyy h:mm a",
        @"euro":         @"dd.MM.yyyy HH:mm",
        @"iso":          @"yyyy-MM-dd",
        @"iso_time":     @"yyyy-MM-dd HH:mm",
    };
}

static NSString *sciFormat(NSDate *date) {
    NSString *fmt = [SCIUtils getStringPref:@"feed_date_format"];
    if (!fmt.length || [fmt isEqualToString:@"default"]) return nil;
    BOOL sec = [[NSUserDefaults standardUserDefaults] boolForKey:@"feed_date_show_seconds"];
    NSString *pattern = sciDateFormats(sec)[fmt];
    if (!pattern) return nil;
    static NSDateFormatter *df = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ df = [NSDateFormatter new]; });
    df.dateFormat = pattern;
    return [df stringFromDate:date];
}

// Per-arity hook generators. When the entry's pref is on, return the custom
// format; otherwise forward to orig with the original arguments.

#define SCI_HOOK0(NAME, SEL_, LABEL, PREF) \
    static NSString *(*orig_##NAME)(NSDate *, SEL); \
    static NSString *hook_##NAME(NSDate *self, SEL _cmd) { \
        if ([SCIUtils getBoolPref:@PREF]) { \
            NSString *r = sciFormat(self); \
            if (r) return r; \
        } \
        return orig_##NAME(self, _cmd); \
    }

#define SCI_HOOK1(NAME, SEL_, LABEL, PREF) \
    static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger); \
    static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1) { \
        if ([SCIUtils getBoolPref:@PREF]) { \
            NSString *r = sciFormat(self); \
            if (r) return r; \
        } \
        return orig_##NAME(self, _cmd, a1); \
    }

#define SCI_HOOK2(NAME, SEL_, LABEL, PREF) \
    static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger); \
    static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2) { \
        if ([SCIUtils getBoolPref:@PREF]) { \
            NSString *r = sciFormat(self); \
            if (r) return r; \
        } \
        return orig_##NAME(self, _cmd, a1, a2); \
    }

#define SCI_HOOK3(NAME, SEL_, LABEL, PREF) \
    static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger, NSInteger); \
    static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2, NSInteger a3) { \
        if ([SCIUtils getBoolPref:@PREF]) { \
            NSString *r = sciFormat(self); \
            if (r) return r; \
        } \
        return orig_##NAME(self, _cmd, a1, a2, a3); \
    }

#define SCI_HOOK4(NAME, SEL_, LABEL, PREF) \
    static NSString *(*orig_##NAME)(NSDate *, SEL, NSInteger, NSInteger, NSInteger, NSInteger); \
    static NSString *hook_##NAME(NSDate *self, SEL _cmd, NSInteger a1, NSInteger a2, NSInteger a3, NSInteger a4) { \
        if ([SCIUtils getBoolPref:@PREF]) { \
            NSString *r = sciFormat(self); \
            if (r) return r; \
        } \
        return orig_##NAME(self, _cmd, a1, a2, a3, a4); \
    }

#define SCI_EMIT_HOOK(NAME, SEL_, LABEL, ARITY, PREF) SCI_HOOK##ARITY(NAME, SEL_, LABEL, PREF)
SCI_DATE_FORMAT_ENTRIES(SCI_EMIT_HOOK)

#define SCI_INSTALL_HOOK(NAME, SEL_, LABEL, ARITY, PREF) do { \
    SEL s = sel_registerName(SEL_); \
    if ([[NSDate class] instancesRespondToSelector:s]) \
        MSHookMessageEx([NSDate class], s, (IMP)hook_##NAME, (IMP *)&orig_##NAME); \
} while (0);

%ctor {
    SCI_DATE_FORMAT_ENTRIES(SCI_INSTALL_HOOK)
}
