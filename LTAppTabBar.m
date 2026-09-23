#import "LTAppTabBar.h"
#import "LTOneHandedMode.h"

@implementation LTAppTabBar

// iOS 11+ picks a side-by-side (icon next to label) layout whenever the tab bar
// lands in a horizontally-regular environment — which on iPad means every time,
// including the one-handed 320x480 mode. In that mode the bar is narrow enough
// that iOS squeezes labels beside the icons instead of beneath them. Reporting
// a compact horizontal size class restores the iPhone-style under-icon labels,
// and only while one-handed mode is active, so full-width iPad usage is
// unchanged. super's other traits are kept so scale/size/safe-area aren't lost.
- (UITraitCollection *)traitCollection {
    if (![UIView instancesRespondToSelector:@selector(traitCollection)]) {
        return nil;
    }
    UITraitCollection *existing = [super traitCollection];
    if (![LTOneHandedMode isActive]) return existing;
    if (existing.horizontalSizeClass != UIUserInterfaceSizeClassRegular) return existing;
    UITraitCollection *compact =
        [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassCompact];
    return [UITraitCollection traitCollectionWithTraitsFromCollections:@[existing, compact]];
}

@end