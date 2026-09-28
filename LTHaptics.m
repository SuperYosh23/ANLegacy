#import "LTHaptics.h"
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>

typedef void (*LTVibrationFn)(SystemSoundID, void *, NSDictionary *);

// Resolved once. The symbol is not in the SDK link stub, so it has to be looked
// up at runtime; a miss simply means no pulse rather than a crash.
static LTVibrationFn LTResolveVibrationFn(void) {
    static LTVibrationFn vibeFn = NULL;
    static BOOL resolved = NO;
    if (!resolved) {
        vibeFn = (LTVibrationFn)dlsym(RTLD_DEFAULT, "AudioServicesPlaySystemSoundWithVibration");
        resolved = YES;
    }
    return vibeFn;
}

@implementation LTHaptics

+ (void)pulse {
    LTVibrationFn vibeFn = LTResolveVibrationFn();
    if (!vibeFn) return;
    NSMutableDictionary *vibe = [NSMutableDictionary dictionary];
    [vibe setObject:[NSArray arrayWithObjects:
                     [NSNumber numberWithBool:NO], [NSNumber numberWithInt:0],
                     [NSNumber numberWithBool:YES], [NSNumber numberWithInt:10], nil]
             forKey:@"VibePattern"];
    [vibe setObject:[NSNumber numberWithInt:1] forKey:@"Intensity"];
    vibeFn(kSystemSoundID_Vibrate, NULL, vibe); // ~10ms motor pulse
}

+ (void)pulseIfEnabledForKey:(NSString *)defaultsKey {
    if (!defaultsKey.length) { [self pulse]; return; }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:defaultsKey]) return;
    [self pulse];
}

@end
