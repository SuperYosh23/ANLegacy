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

@end
