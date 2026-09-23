#import "LTOneHandedMode.h"

static NSString *const kLTOneHandedModeKey = @"LTOneHandedMode";

// The smallest screen the mode is offered on: iPhone 6 (375x667).
static const CGFloat kLTOneHandedMinScreenHeight = 667.0f;

@implementation LTOneHandedMode

+ (BOOL)isSupported {
    return [[UIScreen mainScreen] bounds].size.height >= kLTOneHandedMinScreenHeight;
}

+ (LTOneHandedCorner)mode {
    NSInteger raw = [[NSUserDefaults standardUserDefaults] integerForKey:kLTOneHandedModeKey];
    if (raw < LTOneHandedCornerOff || raw > LTOneHandedCornerBottomRight) return LTOneHandedCornerOff;
    return (LTOneHandedCorner)raw;
}

+ (void)setMode:(LTOneHandedCorner)mode {
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kLTOneHandedModeKey];
}

+ (BOOL)isActive {
    return [self mode] != LTOneHandedCornerOff && [self isSupported];
}

+ (CGSize)virtualSize {
    return CGSizeMake(320.0f, 480.0f);
}

+ (CGRect)frameInBounds:(CGRect)bounds {
    CGSize size = [self virtualSize];
    CGFloat x = ([self mode] == LTOneHandedCornerBottomRight) ? bounds.size.width - size.width : 0.0f;
    CGFloat y = bounds.size.height - size.height;
    return CGRectMake(roundf(x), roundf(y), size.width, size.height);
}

+ (NSString *)labelForMode:(LTOneHandedCorner)mode {
    switch (mode) {
        case LTOneHandedCornerBottomLeft: return @"Bottom Left";
        case LTOneHandedCornerBottomRight: return @"Bottom Right";
        default: return @"Off";
    }
}

+ (NSString *)currentLabel {
    return [self labelForMode:[self mode]];
}

@end
