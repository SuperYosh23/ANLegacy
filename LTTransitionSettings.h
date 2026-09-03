#import <UIKit/UIKit.h>

// Reads/writes the transition speed multiplier stored in NSUserDefaults
// (key "LTTransitionSpeed"). A value of 1.0 is normal speed; lower is
// faster (0.5x), higher is slower (2.0x).
@interface LTTransitionSettings : NSObject
+ (CGFloat)speedMultiplier;
+ (void)setSpeedMultiplier:(CGFloat)multiplier;
+ (CGFloat)durationFor:(CGFloat)baseDuration;
+ (BOOL)animationsEnabled;
+ (void)setAnimationsEnabled:(BOOL)enabled;
@end
