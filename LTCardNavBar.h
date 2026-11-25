#import <UIKit/UIKit.h>

// A navigation bar painted in Material 3's top app bar: a flat surface, a
// hairline divider instead of a shadow, and a title in the on-surface colour.
//
// The native bar cannot be made to look like this on iOS 6 through 11. It
// blurs the content behind it, drops a shadow, and draws its title in the
// system's own typography, none of which can be recoloured.
//
// It is a subclass rather than a replacement so the push and pop behaviour, the
// title, the back button and everything else the navigation controller does
// keep working untouched.
//
// The plain navigation bar is still used in the Native theme.
@interface LTCardNavBar : UINavigationBar
// Paints any navigation bar (including a standard UINavigationBar on iOS 9+,
// where swapping the bar class after creation does not take effect) in the
// modern top-app-bar style. No-op unless a modern theme is selected.
+ (void)applyModernStyleToNavigationBar:(UINavigationBar *)bar;
@end
