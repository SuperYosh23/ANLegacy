#import "LTTransitionSettings.h"

static NSString *const LTTransitionSpeedKey = @"LTTransitionSpeed";
static NSString *const LTAnimationsEnabledKey = @"LTAnimationsEnabled";

@implementation LTTransitionSettings

+ (BOOL)animationsEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:LTAnimationsEnabledKey] == nil) {
        [defaults setBool:YES forKey:LTAnimationsEnabledKey];
        return YES;
    }
    return [defaults boolForKey:LTAnimationsEnabledKey];
}

+ (void)setAnimationsEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:LTAnimationsEnabledKey];
}

+ (CGFloat)speedMultiplier {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:LTTransitionSpeedKey];
    if (!stored) return 1.0f;
    CGFloat value = [stored floatValue];
    if (value < 0.5f) value = 0.5f;
    if (value > 2.0f) value = 2.0f;
    return value;
}

+ (void)setSpeedMultiplier:(CGFloat)multiplier {
    if (multiplier < 0.5f) multiplier = 0.5f;
    if (multiplier > 2.0f) multiplier = 2.0f;
    [[NSUserDefaults standardUserDefaults] setFloat:multiplier forKey:LTTransitionSpeedKey];
}

+ (CGFloat)durationFor:(CGFloat)baseDuration {
    return baseDuration / [self speedMultiplier];
}

#pragma mark - Shared animation entry points

+ (void)animateWithDuration:(CGFloat)baseDuration
                 animations:(void (^)(void))animations {
    [self animateWithDuration:baseDuration delay:0.0f options:0 animations:animations completion:nil];
}

+ (void)animateWithDuration:(CGFloat)baseDuration
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
    [self animateWithDuration:baseDuration delay:0.0f options:0 animations:animations completion:completion];
}

+ (void)animateWithDuration:(CGFloat)baseDuration
                      delay:(CGFloat)delay
                    options:(UIViewAnimationOptions)options
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
    if (!animations) return;
    if (![self animationsEnabled]) {
        // Apply the end state immediately so the UI never depends on the
        // animation running, and still report completion to the caller.
        animations();
        if (completion) completion(YES);
        return;
    }

    // Keep whatever curve the caller chose; otherwise use a gentle ease-in-out.
    // BeginFromCurrentState stops a reversed/interrupted transition from jumping.
    UIViewAnimationOptions opts = options | UIViewAnimationOptionBeginFromCurrentState;
    UIViewAnimationOptions curveMask = (UIViewAnimationOptions)(0xFF << 16);
    if ((opts & curveMask) == 0) opts |= UIViewAnimationOptionCurveEaseInOut;

    [UIView animateWithDuration:[self durationFor:baseDuration]
                          delay:[self durationFor:delay]
                        options:opts
                     animations:animations
                     completion:completion];
}

@end
