#import "LTHaptics.h"
#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>
#import <objc/message.h>

static BOOL LTHapticsAllowed(void) {
    static BOOL checked = NO;
    static BOOL allowed = NO;
    if (!checked) {
        // "on ios 5 or lower all vibration fratures are disabled"
        NSInteger major = [[[[UIDevice currentDevice] systemVersion] componentsSeparatedByString:@"."][0] integerValue];
        allowed = (major >= 6);
        checked = YES;
    }
    return allowed;
}

typedef void (*LTVibrationFn)(SystemSoundID, void *, NSDictionary *);

static NSString *const kLTHapticStrengthKey = @"LTHapticStrength";

// Devices with a Taptic Engine (and iOS 10+ haptic APIs) should use the taptic
// actuator instead of the vibration motor. UIFeedbackGenerator is only available
// on iOS 10+, so older OSes (including iPhone 6s on iOS 9) fall back to the
// existing motor pulse path.
#include <sys/sysctl.h>

static NSString *LTHardwareMachine(void) {
    static NSString *machine = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        size_t size = 0;
        if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) == 0 && size > 0) {
            char *buf = malloc(size);
            if (buf) {
                if (sysctlbyname("hw.machine", buf, &size, NULL, 0) == 0) {
                    machine = [[NSString alloc] initWithUTF8String:buf];
                }
                free(buf);
            }
        }
        if (!machine.length) machine = @"";
    });
    return machine;
}

static BOOL LTForcePrivateTapticEngine(void) {
    static BOOL checked = NO;
    static BOOL force = NO;
    if (checked) return force;
    checked = YES;

    // iPhone 6s (iPhone8,1) / 6s Plus (iPhone8,2) on iOS 9: force private
    // Taptic Engine path instead of the vibration motor fallback.
    NSInteger major = [[[[UIDevice currentDevice] systemVersion] componentsSeparatedByString:@"."][0] integerValue];
    if (major >= 10) return NO;
    NSString *m = LTHardwareMachine();
    if ([m isEqualToString:@"iPhone8,1"] || [m isEqualToString:@"iPhone8,2"]) {
        force = YES;
    }
    return force;
}

static BOOL LTUsePublicTapticEngine(void) {
    static BOOL checked = NO;
    static BOOL useTaptic = NO;
    if (LTForcePrivateTapticEngine()) return NO;
    if (!checked) {
        checked = YES;
        Class genClass = NSClassFromString(@"UIImpactFeedbackGenerator");
        if (!genClass) return NO;
        // Probe for hardware support when available; if we can't tell, prefer the
        // taptic API over driving the vibration motor.
        SEL capSel = NSSelectorFromString(@"capabilities");
        if ([genClass respondsToSelector:capSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id caps = [genClass performSelector:capSel];
#pragma clang diagnostic pop
            if (caps && [caps respondsToSelector:@selector(supportsHaptics)]) {
                useTaptic = ((BOOL (*)(id, SEL))objc_msgSend)(caps, @selector(supportsHaptics));
                return useTaptic;
            }
        }
        useTaptic = YES;
    }
    return useTaptic;
}

static NSInteger LTImpactStyleForStrength(LTHapticStrength strength) {
    // UIImpactFeedbackStyle: Light=0, Medium=1, Heavy=2 (iOS 10+).
    switch (strength) {
        case LTHapticStrengthExtremelyLow:
        case LTHapticStrengthVeryLow:
            return 0; // Light
        case LTHapticStrengthLow:
        case LTHapticStrengthMedium:
            return 1; // Medium
        case LTHapticStrengthHigh:
        case LTHapticStrengthVeryHigh:
        case LTHapticStrengthExtremelyHigh:
        default:
            return 2; // Heavy
    }
}

static id LTPublicTapticGenerator(void) {
    static id generator = nil;
    static LTHapticStrength cachedStrength = (LTHapticStrength)-1;
    if (!LTUsePublicTapticEngine()) return nil;

    LTHapticStrength strength = [LTHaptics strength];
    if (generator && cachedStrength == strength) return generator;

    Class genClass = NSClassFromString(@"UIImpactFeedbackGenerator");
    if (!genClass) return nil;
    NSInteger style = LTImpactStyleForStrength(strength);
    id gen = ((id (*)(id, SEL, NSInteger))objc_msgSend)([genClass alloc], @selector(initWithStyle:), style);
    SEL prepareSel = @selector(prepare);
    if (gen && [gen respondsToSelector:prepareSel]) {
        ((void (*)(id, SEL))objc_msgSend)(gen, prepareSel);
    }
    generator = gen;
    cachedStrength = strength;
    return generator;
}

static BOOL LTPublicTapticPulse(void) {
    id gen = LTPublicTapticGenerator();
    if (!gen) return NO;
    SEL impactSel = @selector(impactOccurred);
    if ([gen respondsToSelector:impactSel]) {
        ((void (*)(id, SEL))objc_msgSend)(gen, impactSel);
    }
    SEL prepareSel = @selector(prepare);
    if ([gen respondsToSelector:prepareSel]) {
        ((void (*)(id, SEL))objc_msgSend)(gen, prepareSel);
    }
    return YES;
}

// Private Taptic Engine fallback for older iOS (e.g. iPhone 6s on iOS 9) where
// UIFeedbackGenerator is unavailable. All lookups are runtime-only.
static id LTPrivateTapticEngine(void) {
    static id engine = nil;
    static BOOL checked = NO;
    if (checked) return engine;
    checked = YES;

    UIDevice *device = [UIDevice currentDevice];
    SEL teSel = NSSelectorFromString(@"_tapticEngine");
    if ([device respondsToSelector:teSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        engine = [device performSelector:teSel];
#pragma clang diagnostic pop
        if (engine) return engine;
    }

    Class cls = NSClassFromString(@"_UITapticEngine");
    if (!cls) cls = NSClassFromString(@"UITapticEngine");
    if (cls) {
        SEL sharedSel = NSSelectorFromString(@"sharedInstance");
        if ([cls respondsToSelector:sharedSel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            engine = [cls performSelector:sharedSel];
#pragma clang diagnostic pop
            if (engine) return engine;
        }
        if ([cls instancesRespondToSelector:@selector(init)]) {
            engine = [[cls alloc] init];
        }
    }
    return engine;
}

static NSInteger LTPrivateFeedbackTypeForStrength(LTHapticStrength strength) {
    // Best-effort mapping for private APIs that take a feedback/actuation type.
    // Common values seen: 0=peek, 1=pop, 2=cancel (3D Touch feedback).
    switch (strength) {
        case LTHapticStrengthExtremelyLow:
        case LTHapticStrengthVeryLow:
        case LTHapticStrengthLow:
            return 0; // peek/light
        case LTHapticStrengthMedium:
        case LTHapticStrengthHigh:
        case LTHapticStrengthVeryHigh:
        case LTHapticStrengthExtremelyHigh:
        default:
            return 1; // pop/stronger
    }
}

static BOOL LTPrivateTapticPulse(void) {
    id engine = LTPrivateTapticEngine();
    if (!engine) return NO;

    NSInteger type = LTPrivateFeedbackTypeForStrength([LTHaptics strength]);
    BOOL did = NO;

    // iOS 9-era private selectors (best-effort, try known variants).
    SEL actuateSel = NSSelectorFromString(@"actuateFeedback:");
    if ([engine respondsToSelector:actuateSel]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(engine, actuateSel, type);
        did = YES;
    }

    SEL actuateIntSel = NSSelectorFromString(@"_actuateFeedback:");
    if (!did && [engine respondsToSelector:actuateIntSel]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(engine, actuateIntSel, type);
        did = YES;
    }

    SEL endSel = NSSelectorFromString(@"endUsingFeedback:");
    SEL prepareUseSel = NSSelectorFromString(@"prepareUsingFeedback:");
    if (!did && [engine respondsToSelector:actuateSel] && [engine respondsToSelector:prepareUseSel]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(engine, prepareUseSel, type);
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(engine, actuateSel, type);
        if ([engine respondsToSelector:endSel]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(engine, endSel, type);
        }
        did = YES;
    }

    // Some implementations expose a simple "vibrate"/"feedback" style action.
    if (!did) {
        SEL simpleSels[] = {
            NSSelectorFromString(@"actuate"),
            NSSelectorFromString(@"_actuate"),
            NSSelectorFromString(@"vibrate"),
            NSSelectorFromString(@"_vibrate")
        };
        for (size_t i = 0; i < sizeof(simpleSels)/sizeof(simpleSels[0]); i++) {
            if ([engine respondsToSelector:simpleSels[i]]) {
                ((void (*)(id, SEL))objc_msgSend)(engine, simpleSels[i]);
                did = YES;
                break;
            }
        }
    }

    SEL warmSel = NSSelectorFromString(@"prepareUsingFeedback:");
    if (did && [engine respondsToSelector:warmSel]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(engine, warmSel, type);
    }
    return did;
}

static BOOL LTUseTapticEngine(void) {
    if (LTForcePrivateTapticEngine()) return YES;
    if (LTUsePublicTapticEngine()) return YES;
    return LTPrivateTapticEngine() != nil;
}

static BOOL LTTapticPulse(void) {
    if (LTForcePrivateTapticEngine()) {
        // Force private path on supported legacy devices (e.g. 6s iOS 9):
        // do not fall back to the vibration motor.
        (void)LTPrivateTapticPulse();
        return YES;
    }
    if (LTPublicTapticPulse()) return YES;
    return LTPrivateTapticPulse();
}

// ---------------------------------------------------------------------------
// Vibration motor fallback (devices without Taptic Engine / older iOS)
// ---------------------------------------------------------------------------
// AudioServices has no public way to time or scale the motor, but the
// long-standing private helper AudioServicesPlaySystemSoundWithVibration does:
// it takes a VibePattern of (vibrate?, milliseconds) pairs plus an Intensity.
// It is absent from the SDK's link stub, so it is resolved at runtime and
// simply no-ops when missing; the public vibrate sound is the fallback.

static LTVibrationFn LTResolveVibrationFn(void) {
    static LTVibrationFn vibeFn = NULL;
    static BOOL resolved = NO;
    if (!resolved) {
        vibeFn = (LTVibrationFn)dlsym(RTLD_DEFAULT, "AudioServicesPlaySystemSoundWithVibration");
        resolved = YES;
    }
    return vibeFn;
}

// Length is the lever that reliably changes the feel: the private Intensity key
// is honoured unevenly across hardware, and an old ERM motor has no intensity
// control at all. Duration alone carries most of the scale, with intensity
// softening the quiet end on top of shorter pulses.
//
// The durations are a geometric ramp rather than even steps, because perceived
// motor strength is not linear in duration. The bottom of the ramp sits below
// what the motor can actually deliver: a 2ms pulse is at the edge of the ERM's
// spin-up, so the two lowest levels are close together on real hardware and
// mostly serve to mean "as faint as this goes" rather than being reliably
// distinguishable. At the top, 30ms is long enough to read as a buzz rather than
// a tick, which is the point of having Very/Extremely High at all.
static NSInteger LTMotorDurationForStrength(LTHapticStrength strength) {
    switch (strength) {
        case LTHapticStrengthExtremelyLow: return 2;
        case LTHapticStrengthVeryLow: return 4;
        case LTHapticStrengthLow: return 7;
        case LTHapticStrengthHigh: return 16;
        case LTHapticStrengthVeryHigh: return 22;
        case LTHapticStrengthExtremelyHigh: return 30;
        default: return 10;
    }
}

static CGFloat LTMotorIntensityForStrength(LTHapticStrength strength) {
    switch (strength) {
        case LTHapticStrengthExtremelyLow: return 0.2f;
        case LTHapticStrengthVeryLow: return 0.35f;
        case LTHapticStrengthLow: return 0.6f;
        default: return 1.0f;
    }
}

static void LTMotorPulse(void) {
    LTHapticStrength strength = [LTHaptics strength];
    NSInteger duration = LTMotorDurationForStrength(strength);
    CGFloat intensity = LTMotorIntensityForStrength(strength);

    LTVibrationFn vibeFn = LTResolveVibrationFn();
    if (vibeFn) {
        NSMutableDictionary *vibe = [NSMutableDictionary dictionary];
        [vibe setObject:[NSArray arrayWithObjects:
                         [NSNumber numberWithBool:NO], [NSNumber numberWithInt:0],
                         [NSNumber numberWithBool:YES], [NSNumber numberWithInt:(int)duration], nil]
                  forKey:@"VibePattern"];
        [vibe setObject:[NSNumber numberWithDouble:intensity] forKey:@"Intensity"];
        vibeFn(kSystemSoundID_Vibrate, NULL, vibe);
        return;
    }

    // No private helper: the public sound is a fixed-length buzz, so strength
    // only affects it in that it cannot. Still better than silence.
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

@implementation LTHaptics

+ (LTHapticStrength)strength {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // An absent key reads back as 0, which is ExtremelyLow, so presence has to be
    // checked explicitly or every fresh install would start at the wrong end of
    // the scale.
    if ([defaults objectForKey:kLTHapticStrengthKey] == nil) return LTHapticStrengthMedium;
    NSInteger raw = [defaults integerForKey:kLTHapticStrengthKey];
    if (raw < LTHapticStrengthExtremelyLow || raw >= LTHapticStrengthCount) return LTHapticStrengthMedium;
    return (LTHapticStrength)raw;
}

+ (void)setStrength:(LTHapticStrength)strength {
    if (strength < LTHapticStrengthExtremelyLow || strength >= LTHapticStrengthCount) return;
    [[NSUserDefaults standardUserDefaults] setInteger:strength forKey:kLTHapticStrengthKey];
    // Recreate the cached taptic generator so the new strength/style takes effect.
    // (LTTapticGenerator caches by strength; invalidation happens on next access,
    // but we clear eagerly here.)
    (void)strength;
}

+ (NSString *)labelForStrength:(LTHapticStrength)strength {
    switch (strength) {
        case LTHapticStrengthExtremelyLow: return @"Extremely Low";
        case LTHapticStrengthVeryLow: return @"Very Low";
        case LTHapticStrengthLow: return @"Low";
        case LTHapticStrengthHigh: return @"High";
        case LTHapticStrengthVeryHigh: return @"Very High";
        case LTHapticStrengthExtremelyHigh: return @"Extremely High";
        default: return @"Medium";
    }
}

+ (NSString *)currentStrengthLabel {
    return [self labelForStrength:[self strength]];
}

+ (void)pulse {
    if (!LTHapticsAllowed()) return;
    if (LTUseTapticEngine()) {
        (void)LTTapticPulse();
        return;
    }
    LTMotorPulse();
}

+ (void)pulseIfEnabledForKey:(NSString *)defaultsKey {
    if (!LTHapticsAllowed()) return;
    if (!defaultsKey.length) { [self pulse]; return; }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:defaultsKey]) return;
    [self pulse];
}

// Pre-warm haptics so the first real pulse fires promptly.
+ (void)prewarm {
    if (!LTHapticsAllowed()) return;
    if (LTUsePublicTapticEngine()) {
        id gen = LTPublicTapticGenerator();
        SEL prepareSel = @selector(prepare);
        if (gen && [gen respondsToSelector:prepareSel]) {
            ((void (*)(id, SEL))objc_msgSend)(gen, prepareSel);
        }
        return;
    }
    id engine = LTPrivateTapticEngine();
    if (engine) {
        NSInteger type = LTPrivateFeedbackTypeForStrength([self strength]);
        SEL warmSel = NSSelectorFromString(@"prepareUsingFeedback:");
        if ([engine respondsToSelector:warmSel]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(engine, warmSel, type);
        }
        return;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Fire the smallest possible pattern to spin up the motor.
        LTVibrationFn vibeFn = LTResolveVibrationFn();
        if (vibeFn) {
            NSMutableDictionary *vibe = [NSMutableDictionary dictionary];
            [vibe setObject:[NSArray arrayWithObjects:
                             [NSNumber numberWithBool:NO], [NSNumber numberWithInt:0],
                             [NSNumber numberWithBool:YES], [NSNumber numberWithInt:1], nil]
                     forKey:@"VibePattern"];
            [vibe setObject:[NSNumber numberWithDouble:0.1f] forKey:@"Intensity"];
            vibeFn(kSystemSoundID_Vibrate, NULL, vibe);
        }
    });
}

@end
