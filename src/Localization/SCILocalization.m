#import "SCILocalization.h"
#import <dlfcn.h>

NSString *const SCILanguagePrefKey = @"sci_language";

static NSBundle *gResourceBundle = nil;
static NSBundle *gLanguageBundle = nil;
static NSString *gLanguageBundleCode = nil;
static dispatch_once_t gResourceOnce;

static NSBundle *resolveResourceBundle(void) {
    // 1) Sideload: cyan copies RyukGram.bundle into the app's resource root.
    NSString *path = [[NSBundle mainBundle] pathForResource:@"RyukGram" ofType:@"bundle"];

    // 2) Jailbreak: .deb drops the bundle into Library/Application Support.
    if (!path) {
        NSArray *fallbacks = @[
            @"/var/jb/Library/Application Support/RyukGram.bundle",
            @"/Library/Application Support/RyukGram.bundle",
        ];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *p in fallbacks) {
            if ([fm fileExistsAtPath:p]) { path = p; break; }
        }
    }

    // 3) Last resort: sibling of the loaded dylib (dev / Feather with loose files).
    if (!path) {
        Dl_info info;
        if (dladdr((const void *)&resolveResourceBundle, &info) && info.dli_fname) {
            NSString *dylibPath = [NSString stringWithUTF8String:info.dli_fname];
            NSString *candidate = [[dylibPath stringByDeletingLastPathComponent]
                                    stringByAppendingPathComponent:@"RyukGram.bundle"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) path = candidate;
        }
    }

    return path ? [NSBundle bundleWithPath:path] : nil;
}

NSBundle *SCILocalizationBundle(void) {
    dispatch_once(&gResourceOnce, ^{ gResourceBundle = resolveResourceBundle(); });
    return gResourceBundle;
}

static NSString *preferredLanguageCode(NSBundle *resource) {
    NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:SCILanguagePrefKey];
    if (pref.length && ![pref isEqualToString:@"system"]) return pref;

    // Match iOS locale against the languages actually shipped in the bundle.
    NSArray<NSString *> *shipped = [resource localizations];
    NSArray<NSString *> *matches = [NSBundle preferredLocalizationsFromArray:shipped
                                                      forPreferences:[NSLocale preferredLanguages]];
    return matches.firstObject ?: @"en";
}

NSString *SCIResolvedLanguageCode(void) {
    NSBundle *b = SCILocalizationBundle();
    return b ? preferredLanguageCode(b) : @"en";
}

static NSBundle *activeLanguageBundle(void) {
    NSBundle *resource = SCILocalizationBundle();
    if (!resource) return nil;

    NSString *code = preferredLanguageCode(resource);
    if (gLanguageBundle && [code isEqualToString:gLanguageBundleCode]) return gLanguageBundle;

    NSString *lprojPath = [resource pathForResource:code ofType:@"lproj"];
    if (!lprojPath) lprojPath = [resource pathForResource:@"en" ofType:@"lproj"];
    gLanguageBundle = lprojPath ? [NSBundle bundleWithPath:lprojPath] : resource;
    gLanguageBundleCode = [code copy];
    return gLanguageBundle;
}

NSString *SCILocalizedString(NSString *key, NSString *fallback) {
    if (key.length == 0) return fallback ?: @"";
    NSBundle *lang = activeLanguageBundle();
    if (!lang) return fallback ?: key;

    // NSBundle returns the key itself when missing (when `value` is nil) —
    // that's our signal to fall back to the English source text.
    NSString *value = [lang localizedStringForKey:key value:@"\x01SCI_MISSING\x01" table:nil];
    if ([value isEqualToString:@"\x01SCI_MISSING\x01"]) return fallback ?: key;
    return value;
}

NSArray<NSDictionary<NSString *, NSString *> *> *SCIAvailableLanguages(void) {
    // `code` is what we persist; `native` is shown in the picker (endonyms read best).
    return @[
        @{ @"code": @"system", @"native": @"System", @"english": @"System default" },
        @{ @"code": @"en",     @"native": @"English", @"english": @"English" },
    ];
}

void SCILocalizationReset(void) {
    gLanguageBundle = nil;
    gLanguageBundleCode = nil;
}
