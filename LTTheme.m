#import "LTTheme.h"

@implementation LTTheme

// UIUserInterfaceStyleDark. The enum is not in the SDKs this app compiles with,
// so the value is spelled out and -userInterfaceStyle is called reflectively.
static const NSInteger LTUserInterfaceStyleDark = 2;

+ (BOOL)isDark {
    UITraitCollection *traits = nil;
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window) {
        NSArray *windows = [[UIApplication sharedApplication] windows];
        if (windows.count) window = [windows objectAtIndex:0];
    }
    if ([window respondsToSelector:@selector(traitCollection)]) {
        traits = window.traitCollection;
    }
    if (!traits && [window.rootViewController respondsToSelector:@selector(traitCollection)]) {
        traits = window.rootViewController.traitCollection;
    }
    if (!traits) return NO;

    SEL selector = NSSelectorFromString(@"userInterfaceStyle");
    if (![traits respondsToSelector:selector]) return NO;
    typedef NSInteger (*LTUserInterfaceStyleFunction)(id, SEL);
    LTUserInterfaceStyleFunction function = (LTUserInterfaceStyleFunction)[traits methodForSelector:selector];
    if (!function) return NO;
    return function(traits, selector) == LTUserInterfaceStyleDark;
}

+ (UIColor *)background {
    return [self isDark] ? [UIColor blackColor] : [UIColor whiteColor];
}

+ (UIColor *)groupedBackground {
    return [self isDark] ? [UIColor blackColor] : [UIColor colorWithWhite:0.937f alpha:1.0f];
}

+ (UIColor *)cellBackground {
    return [self isDark] ? [UIColor colorWithWhite:0.11f alpha:1.0f] : [UIColor whiteColor];
}

+ (UIColor *)fill {
    return [self isDark] ? [UIColor colorWithWhite:0.17f alpha:1.0f] : [UIColor colorWithWhite:0.95f alpha:1.0f];
}

+ (UIColor *)placeholder {
    return [self isDark] ? [UIColor colorWithWhite:0.18f alpha:1.0f] : [UIColor colorWithWhite:0.92f alpha:1.0f];
}

+ (UIColor *)text {
    return [self isDark] ? [UIColor whiteColor] : [UIColor blackColor];
}

+ (UIColor *)secondaryText {
    return [self isDark] ? [UIColor colorWithWhite:0.92f alpha:0.6f] : [UIColor colorWithWhite:0.24f alpha:0.6f];
}

+ (UIColor *)separator {
    return [self isDark] ? [UIColor colorWithWhite:0.33f alpha:0.6f] : [UIColor colorWithWhite:0.24f alpha:0.29f];
}

+ (UIColor *)accent {
    return [UIColor colorWithRed:0.1f green:0.4f blue:0.85f alpha:1.0f];
}

@end
