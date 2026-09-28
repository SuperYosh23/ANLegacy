#import <UIKit/UIKit.h>

// Renders the exact Lucide icon geometry used by the audioNINJA desktop app
// (lucide-react). Lucide icons live on a 24x24 grid, stroke-only, stroke-width
// 2, round caps/joins — so we scale the 24-grid to the requested size and
// stroke with lineWidth = 2 * (size/24). This reproduces the desktop rendering.
@interface LTLucideIcons : NSObject

// Returns a stroked, tinted UIImage of the named Lucide icon at `size` points.
// Returns nil if the icon name is unknown.
+ (UIImage *)iconNamed:(NSString *)name size:(CGFloat)size color:(UIColor *)color;

@end
