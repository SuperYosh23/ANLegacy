#import <Foundation/Foundation.h>

// How hard the motor pulse hits, weakest first. The scale runs in seven steps
// because a motor is coarse: the useful range of VibePattern duration is only a
// few tens of milliseconds, so the ends need finer gradations than three
// evenly spaced levels would give. See LTMotorPulse in LTHaptics.m for the
// duration/intensity behind each one.
typedef NS_ENUM(NSInteger, LTHapticStrength) {
    LTHapticStrengthExtremelyLow = 0,
    LTHapticStrengthVeryLow,
    LTHapticStrengthLow,
    LTHapticStrengthMedium,
    LTHapticStrengthHigh,
    LTHapticStrengthVeryHigh,
    LTHapticStrengthExtremelyHigh,
    LTHapticStrengthCount,
};

// A short haptic pulse.
//
// On devices with a Taptic Engine, this prefers the Taptic Engine over the
// vibration motor: iOS 10+ public UIFeedbackGenerator APIs when available,
// otherwise a runtime-resolved private Taptic Engine fallback for older iOS
// (e.g. iPhone 6s on iOS 9). On devices/OSes without Taptic Engine support, it
// falls back to the vibration motor pulse (AudioServicesPlaySystemSoundWithVibration
// when available, else the public vibrate sound). Vibration/haptics are disabled
// on iOS 5 or lower.
//
// All Taptic/motor APIs are resolved/guarded at runtime because the app deploys
// back to iOS 4 and builds against older SDKs.
@interface LTHaptics : NSObject

// Short tap. Returns immediately; safe to call from a touch handler.
+ (void)pulse;

// Same pulse, but only if the user has not turned haptics off for the given
// preference key.
+ (void)pulseIfEnabledForKey:(NSString *)defaultsKey;

// Pre-warm the vibration motor so the first real pulse fires promptly.
// Call when iPod mode is entered or when the app becomes active.
+ (void)prewarm;

// Strength of the pulse. Medium unless the user has changed it. The stored
// value is the raw enum ordinal, so inserting levels in the middle of the enum
// would silently reinterpret anyone's existing choice.
+ (LTHapticStrength)strength;
+ (void)setStrength:(LTHapticStrength)strength;

+ (NSString *)labelForStrength:(LTHapticStrength)strength;
+ (NSString *)currentStrengthLabel;

@end
