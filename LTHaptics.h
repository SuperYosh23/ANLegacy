#import <Foundation/Foundation.h>

// A short tactile pulse for the vibration motor.
//
// AudioServices has no public way to time the motor, but the long-standing
// private helper AudioServicesPlaySystemSoundWithVibration does. It is absent
// from the SDK's link stub, so it is resolved at runtime with dlsym and simply
// no-ops when it is missing (every device we ship to has it, but a null check
// keeps this from being a crash on anything unexpected).
@interface LTHaptics : NSObject

// ~10ms buzz. Returns immediately; the motor is driven off the main thread by
// the system, so this is safe to call from a touch handler.
+ (void)pulse;

// Same pulse, but only if the user has not turned vibration off for the given
// preference key. Used where the setting already exists.
+ (void)pulseIfEnabledForKey:(NSString *)defaultsKey;

@end
