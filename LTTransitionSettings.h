#import <UIKit/UIKit.h>

// Reads/writes the transition speed multiplier stored in NSUserDefaults
// (key "LTTransitionSpeed"). A value of 1.0 is normal speed; lower values make
// animations slower (0.5x = half speed), higher values make them faster
// (2.0x = double speed). This matches -durationFor:, which divides by it.
@interface LTTransitionSettings : NSObject
+ (CGFloat)speedMultiplier;
+ (void)setSpeedMultiplier:(CGFloat)multiplier;
+ (CGFloat)durationFor:(CGFloat)baseDuration;
+ (BOOL)animationsEnabled;
+ (void)setAnimationsEnabled:(BOOL)enabled;

// Every animation in the app goes through these. They apply the speed setting,
// honour the "Enable Animations" toggle, and add a consistent ease-in-out curve
// (an explicit curve passed to the third overload is kept). If animations are
// off, the final state is applied immediately and the completion still fires.
+ (void)animateWithDuration:(CGFloat)baseDuration
                 animations:(void (^)(void))animations;
+ (void)animateWithDuration:(CGFloat)baseDuration
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion;
+ (void)animateWithDuration:(CGFloat)baseDuration
                      delay:(CGFloat)delay
                    options:(UIViewAnimationOptions)options
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion;
@end
