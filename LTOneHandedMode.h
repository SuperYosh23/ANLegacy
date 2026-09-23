#import <UIKit/UIKit.h>

// "One handed mode" shrinks the whole app down to the classic 320x480
// (non-widescreen) layout and pins it to a bottom corner so it can be reached
// with a thumb. It is only offered on iPhone 6-sized screens and up.
typedef NS_ENUM(NSInteger, LTOneHandedCorner) {
    LTOneHandedCornerOff = 0,
    LTOneHandedCornerBottomLeft,
    LTOneHandedCornerBottomRight,
};

@interface LTOneHandedMode : NSObject

+ (BOOL)isSupported;     // iPhone 6 (667pt tall) and larger
+ (LTOneHandedCorner)mode;
+ (void)setMode:(LTOneHandedCorner)mode;

// YES when a corner is chosen and the screen is big enough to honour it.
+ (BOOL)isActive;

// Logical (unscaled) size the app is drawn at in one-handed mode.
+ (CGSize)virtualSize;

// Where the app's root view goes inside the given screen bounds.
+ (CGRect)frameInBounds:(CGRect)bounds;

+ (NSString *)labelForMode:(LTOneHandedCorner)mode;
+ (NSString *)currentLabel;

@end
