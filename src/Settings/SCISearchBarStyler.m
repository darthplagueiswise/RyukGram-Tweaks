#import "SCISearchBarStyler.h"
#import "../Utils.h"

@implementation SCISearchBarStyler

+ (UIColor *)fieldColor {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) {
            return [UIColor colorWithRed:58/255.0 green:58/255.0 blue:60/255.0 alpha:1.0];
        }
        return [UIColor colorWithRed:190/255.0 green:190/255.0 blue:195/255.0 alpha:1.0];
    }];
}

+ (void)styleSearchBar:(UISearchBar *)sb {
    // Liquid glass already gives the field a proper backdrop.
    if ([SCIUtils getBoolPref:@"liquid_glass_buttons"]) return;

    UITextField *tf = sb.searchTextField;
    if (!tf) return;

    UIColor *fill = [self fieldColor];

    // Hide UIKit's wide rectangular bg; we paint the text field itself
    // so the rounded pill shape survives and UIKit keeps owning layout.
    for (UIView *v in sb.subviews) {
        for (UIView *c in v.subviews) {
            if ([NSStringFromClass(c.class) isEqualToString:@"UISearchBarBackground"]) c.hidden = YES;
        }
    }
    for (UIView *v in tf.subviews) {
        NSString *n = NSStringFromClass(v.class);
        if ([n containsString:@"Background"] || [n containsString:@"Backdrop"]) v.hidden = YES;
    }

    tf.borderStyle = UITextBorderStyleNone;
    tf.backgroundColor = fill;
    tf.layer.backgroundColor = [fill resolvedColorWithTraitCollection:sb.traitCollection].CGColor;
    tf.layer.cornerCurve = kCACornerCurveContinuous;
    tf.layer.cornerRadius = 18;
    tf.layer.masksToBounds = YES;
    tf.opaque = YES;
}

@end
