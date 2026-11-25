#import "LTCardNavBar.h"
#import "LTTheme.h"

// A flat image of one colour, for a bar's backgroundImage or shadowImage.
static UIImage *LTNavFlatImage(CGSize size, UIColor *color) {
    if (size.width <= 0.0f || size.height <= 0.0f) return nil;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
    [color setFill];
    UIRectFill(CGRectMake(0.0f, 0.0f, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    // -stretchableImageWithCapWidth:topCapHeight: is no longer declared by the
    // SDKs this builds against; the left-cap version is the same thing.
    return [image stretchableImageWithLeftCapWidth:1.0f topCapHeight:0.0f];
}

@implementation LTCardNavBar

+ (void)applyModernStyleToNavigationBar:(UINavigationBar *)bar {
    if (!bar || ![LTTheme isModern]) return;

    // Material 3's top app bar is a flat surface with a hairline instead of a
    // shadow, and its title in the on-surface colour. The native bar blurs what
    // is behind it, drops a shadow, and draws its title in the system's own
    // typography, none of which can be recoloured.
    bar.translucent = NO;
    [LTTheme setBarTintColor:[LTTheme background] onBar:bar];
    [LTTheme setTintColor:[LTTheme accent] onView:bar];

    if ([bar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)]) {
        [bar setBackgroundImage:LTNavFlatImage(CGSizeMake(320.0f, 44.0f), [LTTheme background])
                   forBarMetrics:UIBarMetricsDefault];
    }
    if ([bar respondsToSelector:@selector(setShadowImage:)]) {
        [bar setShadowImage:LTNavFlatImage(CGSizeMake(1.0f, 1.0f), [LTTheme separator])];
    }

    if ([bar respondsToSelector:@selector(setTitleTextAttributes:)]) {
        [bar setTitleTextAttributes:@{
            NSForegroundColorAttributeName: [LTTheme text],
            NSFontAttributeName: [UIFont systemFontOfSize:17.0f],
        }];
    }
}

- (id)initWithFrame:(CGRect)frame {
    self = (self = [super initWithFrame:frame]) ? self : nil;
    if (self) [self lt_applyModernStyle];
    return self;
}

- (void)lt_applyModernStyle {
    [LTCardNavBar applyModernStyleToNavigationBar:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (![LTTheme isModern]) return;

    // Material 3 centres the title in the bar. UIKit centres it in the space
    // left over after the back button, which puts it visibly off-centre, so it
    // is only recentred when there is no back button to make room for.
    if (self.topItem.leftBarButtonItem) return;
    for (UIView *subview in self.subviews) {
        if (![subview isKindOfClass:[UILabel class]]) continue;
        CGRect label = subview.frame;
        CGFloat width = CGRectGetWidth(self.bounds) - 32.0f;
        if (width <= 0.0f) continue;
        label.origin.x = 16.0f;
        label.size.width = width;
        subview.frame = label;
    }
}

@end
