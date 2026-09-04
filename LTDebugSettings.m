#import "LTDebugSettings.h"

static BOOL LTForceNonWidescreen = NO;
static BOOL LTForceWidescreen = NO;

@implementation LTDebugSettings

+ (BOOL)forceNonWidescreen {
    return LTForceNonWidescreen;
}

+ (void)setForceNonWidescreen:(BOOL)on {
    LTForceNonWidescreen = on;
    if (on) LTForceWidescreen = NO;
}

+ (BOOL)forceWidescreen {
    return LTForceWidescreen;
}

+ (void)setForceWidescreen:(BOOL)on {
    LTForceWidescreen = on;
    if (on) LTForceNonWidescreen = NO;
}

@end