#import "LTTransitionSettings.h"

static NSString *const LTTransitionSpeedKey = @"LTTransitionSpeed";

@implementation LTTransitionSettings

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
