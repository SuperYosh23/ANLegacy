#import "LTLyricsSettings.h"

NSString * const LTLyricsOffsetKey = @"LTLyricsOffset";

double LTLyricsOffset(void) {
    return [[NSUserDefaults standardUserDefaults] doubleForKey:LTLyricsOffsetKey];
}

void LTSetLyricsOffset(double seconds) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:seconds forKey:LTLyricsOffsetKey];
    [defaults synchronize];
}