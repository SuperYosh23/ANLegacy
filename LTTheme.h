#import <UIKit/UIKit.h>

// Central place for the few colors the app needs to change between light and
// dark appearance. The app ships against old SDKs (iOS 9.3 / 11.2), so it cannot
// use the iOS 13 dynamic system colors: dark mode is detected at runtime and the
// matching plain color is returned. On iOS 12 and older -isDark is always NO.
@interface LTTheme : NSObject

+ (BOOL)isDark;

+ (UIColor *)background;         // page / table background
+ (UIColor *)groupedBackground;  // behind grouped (settings-style) content
+ (UIColor *)cellBackground;     // raised surface inside grouped content
+ (UIColor *)fill;               // subtle fills (buttons, chips)
+ (UIColor *)placeholder;        // artwork placeholders
+ (UIColor *)text;               // primary text
+ (UIColor *)secondaryText;      // captions, detail text
+ (UIColor *)separator;
+ (UIColor *)accent;

@end
