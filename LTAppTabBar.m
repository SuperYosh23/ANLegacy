#import "LTAppTabBar.h"
#import "LTOneHandedMode.h"
#import "LTTheme.h"
#import <objc/message.h>

@implementation LTAppTabBar

// A flat image of one colour, for the bar's backgroundImage or shadowImage.
static UIImage *LTBarFlatImage(CGSize size, UIColor *color) {
    if (size.width <= 0.0f || size.height <= 0.0f) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
    [color setFill];
    UIRectFill(CGRectMake(0.0f, 0.0f, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image stretchableImageWithLeftCapWidth:1.0f topCapHeight:0.0f];
}

// Material 3's navigation bar: flat, no shadow, a hairline along the top, and
// the item colours from the theme.
//
// The native tab bar cannot be recoloured to this on iOS 6 through 11 - it
// blurs what is behind it and drops a shadow. The plain bar is still used in
// the Native theme, where it is exactly what it should be.
- (void)lt_applyModernStyle {
    if (![LTTheme isModern]) return;

    if ([self respondsToSelector:@selector(setTranslucent:)]) { BOOL no = NO; NSInvocation *inv = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(setTranslucent:)]]; [inv setSelector:@selector(setTranslucent:)]; [inv setTarget:self]; [inv setArgument:&no atIndex:2]; [inv invoke]; }
    [LTTheme setBarTintColor:[LTTheme background] onBar:self];
    // UITabBar exposes the background as a plain property, not the
    // setBackgroundImage:forBarMetrics: pair the navigation bar has.
    self.backgroundImage = LTBarFlatImage(CGSizeMake(320.0f, 49.0f), [LTTheme background]);
    // A hairline along the top instead of a shadow.
    self.shadowImage = LTBarFlatImage(CGSizeMake(1.0f, 1.0f), [LTTheme separator]);

    // -unselectedItemTintColor arrived in iOS 10, which is newer than the SDK
    // this armv7 slice builds against, so it is called reflectively.
    if ([self respondsToSelector:@selector(setUnselectedItemTintColor:)]) {
        SEL selector = NSSelectorFromString(@"setUnselectedItemTintColor:");
        void (*setTint)(id, SEL, UIColor *) = (void (*)(id, SEL, UIColor *))objc_msgSend;
        setTint(self, selector, [LTTheme secondaryText]);
    }
    [LTTheme setTintColor:[LTTheme accent] onView:self];

    // The item carries its own title attributes; the bar has no setter for
    // them.
    UIFont *font = [UIFont systemFontOfSize:11.0f];
    for (UITabBarItem *item in self.items) {
        [item setTitleTextAttributes:@{NSFontAttributeName: font} forState:UIControlStateNormal];
        [item setTitleTextAttributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: [LTTheme accent],
        } forState:UIControlStateSelected];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self lt_applyModernStyle];
}

@end