#import "LTArtworkBackground.h"

static NSString *const LTArtworkBackgroundKey = @"LTPlayerArtworkBackground";

@implementation LTArtworkBackground

+ (BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id stored = [defaults objectForKey:LTArtworkBackgroundKey];
    if (stored == nil) return YES;
    return [defaults boolForKey:LTArtworkBackgroundKey];
}

+ (void)setEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:LTArtworkBackgroundKey];
    [defaults synchronize];
}

@end
