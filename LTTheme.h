#import <UIKit/UIKit.h>

// Central place for the few colors the app needs to change between light and
// dark appearance. The app ships against old SDKs (iOS 9.3 / 11.2), so it cannot
// use the iOS 13 dynamic system colors: dark mode is detected at runtime and the
// matching plain color is returned. On iOS 12 and older -isDark is always NO.
// Three looks. Native is what the app has always shipped: the standard UIKit
// palette, only going dark when the OS says so. The modern pair is a rounded,
// card-based look; Modern Dark is the same chrome on a dark canvas.
typedef NS_ENUM(NSInteger, LTThemeStyle) {
    LTThemeStyleNative = 0,
    LTThemeStyleModernLight = 1,
    LTThemeStyleModernDark = 2,
};

// Posted after the theme changes, so the UI can rebuild itself. The app
// rebuilds its root rather than trying to recolour every live view, which
// would miss anything that cached a colour.
extern NSString *const LTThemeDidChangeNotification;

@interface LTTheme : NSObject

// Whether this device can run the modern themes.
//
// They need iOS 7. The modern theme is drawn with UIKit rather than served as
// a web page, so it is not the web view that rules it out any more - it is
// that the theme reaches for properties and classes which arrived with iOS 7,
// and on iOS 6 those are unrecognised selectors.
//
// Where this is false, the theme row is hidden and the app stays on the native
// theme even if a modern one was chosen elsewhere.
+ (BOOL)supportsModernThemes;

+ (LTThemeStyle)currentTheme;
+ (void)setCurrentTheme:(LTThemeStyle)theme;

// Name for the theme picker.
+ (NSString *)nameForTheme:(LTThemeStyle)theme;

// The dark/light decision, now driven by the selected theme rather than only
// by the OS. Native still follows the OS; the modern pair is fixed.
+ (BOOL)isDark;

// Modern themes use larger corner radii and a softer accent than native.
+ (BOOL)isModern;
+ (CGFloat)cornerRadius;       // standard corner radius for cards and buttons
+ (CGFloat)largeCornerRadius;  // for larger surfaces (artwork, sheets)

// Drops the cached appearance probe. Call from any trait-collection change
// callback; +isDark is otherwise cached because it was doing a window walk and
// runtime selector lookup on every single colour access.
+ (void)refreshAppearance;

// Colours for a given theme, regardless of which one is active. Used for the
// little palette previews in the theme picker.
+ (UIColor *)backgroundForTheme:(LTThemeStyle)theme;
+ (UIColor *)textForTheme:(LTThemeStyle)theme;
+ (UIColor *)accentForTheme:(LTThemeStyle)theme;

+ (UIColor *)background;         // page / table background
+ (UIColor *)groupedBackground;  // behind grouped (settings-style) content
+ (UIColor *)cellBackground;     // raised surface inside grouped content
+ (UIColor *)fill;               // subtle fills (buttons, chips)
+ (UIColor *)placeholder;        // artwork placeholders
+ (UIColor *)text;               // primary text
+ (UIColor *)secondaryText;      // captions, detail text
+ (UIColor *)separator;
+ (UIColor *)accent;

// Accent colour presets. Index 0 is "Theme Default", which keeps the classic
// look (rose for the modern themes, blue for Native). Any other index overrides
// the accent in every theme. The choice is persisted and applies on all iOS
// versions, including those without a system tint colour.
+ (NSArray *)accentPresetNames;
+ (NSInteger)accentPresetIndex;
+ (void)setAccentPresetIndex:(NSInteger)index;
+ (NSString *)currentAccentLabel;
+ (UIColor *)accentSwatchForPresetIndex:(NSInteger)index;

+ (UIStatusBarStyle)statusBarStyle;
+ (UIColor *)statusBarBackgroundColor;

// Whether the surfaces the app draws itself should be skeuomorphic.
//
// On iOS 6 and earlier the system drew the chrome - the woven background of
// a grouped table, the raised rows, the glossy bars - and the app's own
// surfaces were the only flat things on screen. The app draws its own
// surfaces now, so on those systems they are given the old look to match.
+ (BOOL)usesSkeuomorphicSurfaces;

// Sets a view's tint colour, where the platform has one.
//
// -tintColor arrived in iOS 7 and the 3GS runs 6.1.6, where sending it is an
// unrecognised selector and a crash on launch. Anything that tints a view has
// to go through here.
+ (void)setTintColor:(UIColor *)color onView:(UIView *)view;

// Sets a bar's background colour, where the platform has one. -barTintColor
// is iOS 7, so it has to be checked.
+ (void)setBarTintColor:(UIColor *)color onBar:(UIView *)bar;

// Sets a segmented control's title font on every supported iOS, and forces the
// compact Bar style on the old systems that still honour it.
//
// -setTitleTextAttributes:forState: is iOS 5+. On iOS 4 there is no public way
// to set the font, so the labels inside the control's private segment views are
// set directly. Without both parts iOS 4 falls back to the tall Plain style and
// draws its default (large) font in a short frame, so the text overflows the
// button - the subtab problem seen on the 3GS.
+ (void)setTitleFont:(UIFont *)font forSegmentedControl:(UISegmentedControl *)control;

// Forces the compact Bar style on the iOS versions that still honour it. Used
// on its own where the caller also sets title colours and so cannot go through
// -setTitleFont:forSegmentedControl: without replacing them.
+ (void)setCompactStyleForSegmentedControl:(UISegmentedControl *)control;

// A colour scaled towards black (factor below 1) or towards white (above 1).
// Used for the gradient stops, where an alpha cannot do the job: the stops have
// to stay opaque or the card shows the background through them.
+ (UIColor *)shade:(UIColor *)color by:(CGFloat)factor;

@end
