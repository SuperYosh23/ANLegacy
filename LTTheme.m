#import "LTTheme.h"
#import "LTLog.h"
#import "LTCardControls.h"
#import <objc/message.h>
#import <objc/runtime.h>

// -barTintColor is declared by the SDK on the bar classes that have it
// (UIToolbar, UINavigationBar), but not on UIView, so a helper that takes a
// UIView cannot call it without a declaration of its own.
@interface UIView (LTBarTintCompat)
- (void)setBarTintColor:(UIColor *)color;
@end

@implementation LTTheme

// UIUserInterfaceStyleDark. The enum is not in the SDKs this app compiles with,
// so the value is spelled out and -userInterfaceStyle is called reflectively.
static const NSInteger LTUserInterfaceStyleDark = 2;

NSString *const LTThemeDidChangeNotification = @"LTThemeDidChangeNotification";

static const NSString *kLTThemeKey = @"LTThemeStyle";
static const NSString *kLTAccentKey = @"LTAccentStyle";

// Preset accents, as light/dark hex pairs. Index 0 is a sentinel meaning
// "use the theme's own default"; the rest are Material 3-ish hues with a
// lighter companion for dark surfaces so text and icons stay legible.
static NSInteger LTAccentCount(void) { return 7; }

static NSString *LTAccentNameForIndex(NSInteger index) {
    switch (index) {
        case 0: return @"Theme Default";
        case 1: return @"Rose";
        case 2: return @"Blue";
        case 3: return @"Green";
        case 4: return @"Purple";
        case 5: return @"Amber";
        case 6: return @"Teal";
        default: return @"Theme Default";
    }
}

static int LTAccentLightHex(NSInteger index) {
    switch (index) {
        case 1: return 0xB8475E; // rose
        case 2: return 0x1A73E8; // blue
        case 3: return 0x1E8E3E; // green
        case 4: return 0x7B1FA2; // purple
        case 5: return 0xE8710C; // amber
        case 6: return 0x00897B; // teal
        default: return 0;
    }
}

static int LTAccentDarkHex(NSInteger index) {
    switch (index) {
        case 1: return 0xFF8A9B;
        case 2: return 0x8AB4F8;
        case 3: return 0x81C995;
        case 4: return 0xCE9FFC;
        case 5: return 0xFFB74D;
        case 6: return 0x5AD4C1;
        default: return 0;
    }
}

static BOOL LTIsDarkCached = NO;
static BOOL LTIsDarkCacheValid = NO;

+ (LTThemeStyle)currentTheme {
    NSInteger raw = [[NSUserDefaults standardUserDefaults] integerForKey:(NSString *)kLTThemeKey];
    if (raw < 0 || raw > LTThemeStyleModernDark) return LTThemeStyleNative;
    // A modern theme that was chosen on a newer device must not be carried
    // onto one that cannot run it: the stored choice is kept, but the app
    // falls back to the native theme here.
    if (raw != LTThemeStyleNative && ![self supportsModernThemes]) return LTThemeStyleNative;
    return (LTThemeStyle)raw;
}

+ (void)setCurrentTheme:(LTThemeStyle)theme {
    if (theme < 0 || theme > LTThemeStyleModernDark) theme = LTThemeStyleNative;
    // Belt and braces: the theme row is hidden where the modern themes cannot
    // run, but nothing should be able to select one here either.
    if (theme != LTThemeStyleNative && ![self supportsModernThemes]) theme = LTThemeStyleNative;
    if (theme == [self currentTheme]) return;
    [[NSUserDefaults standardUserDefaults] setInteger:theme forKey:(NSString *)kLTThemeKey];
    [self refreshAppearance];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTThemeDidChangeNotification object:nil];
}

+ (BOOL)supportsModernThemes {
    // The modern themes need iOS 7.
    //
    // They are drawn with UIKit rather than served as a web page, so the old
    // limits - a WKWebView, which needs iOS 9, and a screen big enough for
    // the desktop layout - no longer apply. What does apply is iOS 7 itself:
    // the modern theme reaches for properties and classes that arrived with
    // it, and on iOS 6 those are unrecognised selectors, which is a crash
    // rather than a missing feature.
    //
    // The version is read from the device rather than the SDK, since this app
    // runs on far older systems than it compiles against.
    NSInteger major = [[[UIDevice currentDevice] systemVersion] integerValue];
    return major >= 7;
}

+ (NSString *)nameForTheme:(LTThemeStyle)theme {
    switch (theme) {
        case LTThemeStyleModernLight: return @"Modern Light";
        case LTThemeStyleModernDark: return @"Modern Dark";
        case LTThemeStyleNative:
        default: return @"Native";
    }
}

+ (BOOL)isModern {
    return [self currentTheme] != LTThemeStyleNative;
}

+ (BOOL)isDark {
    @synchronized (self) {
        if (LTIsDarkCacheValid) return LTIsDarkCached;
        LTIsDarkCached = [self resolveIsDark];
        LTIsDarkCacheValid = YES;
        return LTIsDarkCached;
    }
}

+ (void)refreshAppearance {
    @synchronized (self) { LTIsDarkCacheValid = NO; }
}

+ (BOOL)resolveIsDark {
    LTThemeStyle theme = [self currentTheme];
    if (theme == LTThemeStyleModernLight) return NO;
    if (theme == LTThemeStyleModernDark) return YES;
    // Native: follow the OS (iOS 13+ trait collection). Unavailable on iOS 4/5.
    id traits = nil;
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window) {
        NSArray *windows = [[UIApplication sharedApplication] windows];
        if ([windows count]) window = [windows objectAtIndex:0];
    }
    if (window && [window respondsToSelector:@selector(traitCollection)]) {
        traits = [window performSelector:@selector(traitCollection)];
    }
    id root = window ? [window rootViewController] : nil;
    if (!traits && root && [root respondsToSelector:@selector(traitCollection)]) {
        traits = [root performSelector:@selector(traitCollection)];
    }
    if (!traits) return NO;

    SEL selector = NSSelectorFromString(@"userInterfaceStyle");
    if (![traits respondsToSelector:selector]) return NO;
    typedef NSInteger (*LTUserInterfaceStyleFunction)(id, SEL);
    LTUserInterfaceStyleFunction function = (LTUserInterfaceStyleFunction)[traits methodForSelector:selector];
    if (!function) return NO;
    return function(traits, selector) == LTUserInterfaceStyleDark;
}

+ (CGFloat)cornerRadius {
    return [self isModern] ? 12.0f : 6.0f;
}

+ (CGFloat)largeCornerRadius {
    return [self isModern] ? 16.0f : 8.0f;
}

// MARK: - Colors

// The modern pair uses the desktop app's Material 3 tokens verbatim, so the
// two look the same rather than merely similar. The values are the ones from
// the desktop app's @theme block: surface-dim, surface-container,
// surface-container-high, surface-container-highest, on-surface,
// on-surface-variant, outline-variant and primary.
static UIColor *LTRGB(int hex) {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0f
                           green:((hex >> 8) & 0xFF) / 255.0f
                            blue:(hex & 0xFF) / 255.0f
                           alpha:1.0f];
}

+ (UIStatusBarStyle)statusBarStyle {
    LTThemeStyle t = [self currentTheme];
    if (t == LTThemeStyleModernDark) {
        return (UIStatusBarStyle)1; /* UIStatusBarStyleLightContent */
    }
    return UIStatusBarStyleDefault;
}

+ (UIColor *)statusBarBackgroundColor {
    LTThemeStyle t = [self currentTheme];
    if (t == LTThemeStyleModernDark) {
        return [UIColor blackColor];
    }
    return [UIColor whiteColor];
}

+ (UIColor *)backgroundForTheme:(LTThemeStyle)t {
    if (t == LTThemeStyleModernLight) return LTRGB(0xFFFBFE);
    if (t == LTThemeStyleModernDark) return LTRGB(0x1C1B1F);
    return [self isDark] ? [UIColor blackColor] : [UIColor whiteColor];
}

+ (UIColor *)background {
    return [self backgroundForTheme:[self currentTheme]];
}

+ (UIColor *)groupedBackground {
    LTThemeStyle t = [self currentTheme];
    if (t == LTThemeStyleModernLight) return LTRGB(0xFEF7FF);   // surface-dim
    if (t == LTThemeStyleModernDark) return LTRGB(0x141218);    // surface-dim
    return [self isDark] ? [UIColor blackColor] : [UIColor colorWithWhite:0.937f alpha:1.0f];
}

+ (UIColor *)cellBackground {
    LTThemeStyle t = [self currentTheme];
    if (t == LTThemeStyleModernLight) return LTRGB(0xF0E9F1);   // surface-container
    if (t == LTThemeStyleModernDark) return LTRGB(0x211F26);    // surface-container
    return [self isDark] ? [UIColor colorWithWhite:0.11f alpha:1.0f] : [UIColor whiteColor];
}

+ (UIColor *)fill {
    LTThemeStyle t = [self currentTheme];
    if (t == LTThemeStyleModernLight) return LTRGB(0xE6E0E9);   // surface-container-high
    if (t == LTThemeStyleModernDark) return LTRGB(0x2B2930);    // surface-container-high
    return [self isDark] ? [UIColor colorWithWhite:0.17f alpha:1.0f] : [UIColor colorWithWhite:0.95f alpha:1.0f];
}

+ (UIColor *)placeholder {
    LTThemeStyle t = [self currentTheme];
    if (t == LTThemeStyleModernLight) return LTRGB(0xDCD6DE);   // surface-container-highest
    if (t == LTThemeStyleModernDark) return LTRGB(0x36343B);    // surface-container-highest
    return [self isDark] ? [UIColor colorWithWhite:0.18f alpha:1.0f] : [UIColor colorWithWhite:0.92f alpha:1.0f];
}

+ (UIColor *)textForTheme:(LTThemeStyle)t {
    if (t == LTThemeStyleModernLight) return LTRGB(0x1D1B20);   // on-surface
    if (t == LTThemeStyleModernDark) return LTRGB(0xE6E0E9);    // on-surface
    return [self isDark] ? [UIColor whiteColor] : [UIColor blackColor];
}

+ (UIColor *)text {
    return [self textForTheme:[self currentTheme]];
}

+ (UIColor *)secondaryText {
    LTThemeStyle t = [self currentTheme];
    if (t == LTThemeStyleModernLight) return LTRGB(0x49454F);   // on-surface-variant
    if (t == LTThemeStyleModernDark) return LTRGB(0xCAC4D0);    // on-surface-variant
    return [self isDark] ? [UIColor colorWithWhite:0.92f alpha:0.6f] : [UIColor colorWithWhite:0.24f alpha:0.6f];
}

+ (UIColor *)separator {
    LTThemeStyle t = [self currentTheme];
    if (t == LTThemeStyleModernLight) return LTRGB(0xCAC4D0);   // outline-variant
    if (t == LTThemeStyleModernDark) return LTRGB(0x49454F);    // outline-variant
    return [self isDark] ? [UIColor colorWithWhite:0.33f alpha:0.6f] : [UIColor colorWithWhite:0.24f alpha:0.29f];
}

+ (void)setTintColor:(UIColor *)color onView:(UIView *)view {
    if (!view || !color) return;
    if (![view respondsToSelector:@selector(setTintColor:)]) return;
    [(id)view performSelector:@selector(setTintColor:) withObject:color];
}

+ (void)setBarTintColor:(UIColor *)color onBar:(UIView *)bar {
    if (!bar || !color) return;
    if (![bar respondsToSelector:@selector(setBarTintColor:)]) return;
    [(id)bar performSelector:@selector(setBarTintColor:) withObject:color];
}

// iOS 4 keeps the label for each segment inside a private view. There is no
// public font API on that system, so the only way to keep the title from
// overflowing a short control is to set the font on those labels directly.
+ (NSInteger)lt_applyFont:(UIFont *)font toLabelTree:(UIView *)view {
    NSInteger count = 0;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            label.font = font;
            // The old control caches its segment images. Without an explicit
            // redraw the new font is not visible until a tap changes the
            // selection and forces one.
            [label setNeedsDisplay];
            count++;
        }
        count += [self lt_applyFont:font toLabelTree:subview];
    }
    return count;
}

+ (void)setCompactStyleForSegmentedControl:(UISegmentedControl *)control {
    if (!control) return;
    // On iOS 4/5/6 the segment style still matters. The default Plain style is
    // built for a ~44pt control with a large font; squeezing it into the 30pt
    // frame the subtabs use makes the text spill out of the button. Bar style
    // is the compact one and matches the frame. Ignored (and deprecated) from
    // iOS 7, where the platform draws all styles the same way.
    if (![control respondsToSelector:@selector(setSegmentedControlStyle:)]) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    control.segmentedControlStyle = UISegmentedControlStyleBar;
#pragma clang diagnostic pop
}

+ (void)setTitleFont:(UIFont *)font forSegmentedControl:(UISegmentedControl *)control {
    if (!control || !font) return;
    [self setCompactStyleForSegmentedControl:control];

    // On iOS 4 the native control's private labels are reset on every layout,
    // so the compact subclass keeps the font and re-applies it in -layoutSubviews.
    // Only iOS 4 needs the layout-time reapplication; from iOS 5 the public
    // title-attribute API is both available and reliable.
    if ([[[UIDevice currentDevice] systemVersion] integerValue] < 5 &&
        [control isKindOfClass:[LTCompactSegmentedControl class]]) {
        [(LTCompactSegmentedControl *)control setCompactTitleFont:font];
        [control setNeedsDisplay];
        return;
    }

    if ([control respondsToSelector:@selector(setTitleTextAttributes:forState:)]) {
        // iOS 5+ public API. UITextAttributeFont is read only inside this branch,
        // so the iOS 4 runtime never touches that newer data symbol.
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:UITextAttributeFont];
        [control setTitleTextAttributes:attributes forState:UIControlStateNormal];
        [control setTitleTextAttributes:attributes forState:UIControlStateHighlighted];
        [control setTitleTextAttributes:attributes forState:UIControlStateSelected];
        [control setTitleTextAttributes:attributes forState:UIControlStateDisabled];
        // The old control does not redraw just because its labels changed.
        // Without this the new font only shows up after a tap, when the
        // selection change happens to trigger a redraw.
        [control setNeedsDisplay];
        return;
    }

    // iOS 4 fallback (the 3GS): no -setTitleTextAttributes:forState: exists.
    NSInteger labels = [self lt_applyFont:font toLabelTree:control];
    [control setNeedsDisplay];
    LTLog(@"LTSEG iOS4 font=%.1f labels=%d h=%.0f w=%.0f",
          font.pointSize, (int)labels, CGRectGetHeight(control.frame), CGRectGetWidth(control.frame));
}

+ (UIColor *)shade:(UIColor *)color by:(CGFloat)factor {
    CGFloat r = 0.0f, g = 0.0f, b = 0.0f, a = 1.0f;
    BOOL got = NO;
    if ([color respondsToSelector:@selector(getRed:green:blue:alpha:)])
        got = ((BOOL(*)(id,SEL,CGFloat*,CGFloat*,CGFloat*,CGFloat*))objc_msgSend)(color, @selector(getRed:green:blue:alpha:), &r, &g, &b, &a);
    if (!got) {
        CGFloat w = 1;
        if ([color respondsToSelector:@selector(getWhite:alpha:)] && ((BOOL(*)(id,SEL,CGFloat*,CGFloat*))objc_msgSend)(color, @selector(getWhite:alpha:), &w, &a)) { r=g=b=w; got=YES; }
    }
    if (!got) return color;
    if (factor >= 1.0f) {
        CGFloat t = factor - 1.0f;
        r += (1.0f - r) * t;
        g += (1.0f - g) * t;
        b += (1.0f - b) * t;
    } else {
        r *= factor;
        g *= factor;
        b *= factor;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

+ (BOOL)usesSkeuomorphicSurfaces {
    // The modern themes are deliberately modern, so they never take this on.
    if ([self isModern]) return NO;
    NSInteger major = [[[UIDevice currentDevice] systemVersion] integerValue];
    return major < 7;
}

+ (NSInteger)accentPresetIndex {
    NSInteger raw = [[NSUserDefaults standardUserDefaults] integerForKey:(NSString *)kLTAccentKey];
    if (raw < 0 || raw >= LTAccentCount()) return 0;
    return raw;
}

+ (void)setAccentPresetIndex:(NSInteger)index {
    if (index < 0 || index >= LTAccentCount()) index = 0;
    if (index == [self accentPresetIndex]) return;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:(NSString *)kLTAccentKey];
    // The accent is cached in a few places (nav bars, switches), so rebuild the
    // UI the same way a theme change does.
    [[NSNotificationCenter defaultCenter] postNotificationName:LTThemeDidChangeNotification object:nil];
}

+ (NSString *)currentAccentLabel {
    return LTAccentNameForIndex([self accentPresetIndex]);
}

+ (NSArray *)accentPresetNames {
    NSMutableArray *names = [NSMutableArray array];
    for (NSInteger i = 0; i < LTAccentCount(); i++) {
        [names addObject:LTAccentNameForIndex(i)];
    }
    return names;
}

+ (UIColor *)accentSwatchForPresetIndex:(NSInteger)index {
    if (index == 0) {
        // Show the theme's own default in the Default row.
        LTThemeStyle t = [self currentTheme];
        if (t == LTThemeStyleModernLight) return LTRGB(0xB8475E);
        if (t == LTThemeStyleModernDark) return LTRGB(0xFF8A9B);
        return [UIColor colorWithRed:0.1f green:0.4f blue:0.85f alpha:1.0f];
    }
    int hex = [self isDark] ? LTAccentDarkHex(index) : LTAccentLightHex(index);
    if (!hex) hex = LTAccentLightHex(index);
    return hex ? LTRGB(hex) : [self accentSwatchForPresetIndex:0];
}

+ (UIColor *)accentForTheme:(LTThemeStyle)t {
    // Native means the platform's own palette, so the accent override (which
    // is only offered for the Modern themes) has no effect there.
    if (t != LTThemeStyleNative) {
        NSInteger index = [self accentPresetIndex];
        if (index > 0) {
            int hex = (t == LTThemeStyleModernDark) ? LTAccentDarkHex(index) : LTAccentLightHex(index);
            if (!hex) hex = LTAccentLightHex(index);
            if (hex) return LTRGB(hex);
        }
    }
    if (t == LTThemeStyleModernLight) return LTRGB(0xB8475E);   // primary
    if (t == LTThemeStyleModernDark) return LTRGB(0xFF8A9B);    // primary
    return [UIColor colorWithRed:0.1f green:0.4f blue:0.85f alpha:1.0f];
}

+ (UIColor *)accent {
    return [self accentForTheme:[self currentTheme]];
}

@end