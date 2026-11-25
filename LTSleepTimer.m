#import "LTSleepTimer.h"
#import "LTPlayerController.h"
#import "LTLog.h"

NSString * const LTSleepTimerDidChangeNotification = @"LTSleepTimerDidChange";

static NSString * const kLTSleepDeadlineKey = @"LTSleepTimerDeadline";

@implementation LTSleepTimer

+ (LTSleepTimer *)shared {
    static LTSleepTimer *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[LTSleepTimer alloc] init]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        // A deadline set before the last quit has to be picked up, otherwise the
        // audio would keep playing forever with no way to see why.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(checkExpired)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        // Unretained on purpose: the run loop holds scheduled timers, and this
        // singleton lives for the process anyway.
        [NSTimer scheduledTimerWithTimeInterval:30.0
                                         target:self
                                       selector:@selector(checkExpired)
                                       userInfo:nil
                                        repeats:YES];
        [self checkExpired];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSDate *)deadline {
    NSTimeInterval stamp = [[NSUserDefaults standardUserDefaults] doubleForKey:kLTSleepDeadlineKey];
    if (stamp <= 0.0) return nil;
    return [NSDate dateWithTimeIntervalSince1970:stamp];
}

- (BOOL)isActive {
    return [self remainingSeconds] > 0;
}

- (NSInteger)remainingMinutes {
    NSTimeInterval seconds = [self remainingSeconds];
    if (seconds <= 0.0) return 0;
    return (NSInteger)ceil(seconds / 60.0);
}

- (NSTimeInterval)remainingSeconds {
    NSDate *deadline = [self deadline];
    if (!deadline) return 0.0;
    return [deadline timeIntervalSinceNow];
}

- (void)startWithMinutes:(NSInteger)minutes {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (minutes <= 0) {
        [self cancel];
        return;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(NSTimeInterval)minutes * 60.0];
    [defaults setDouble:[deadline timeIntervalSince1970] forKey:kLTSleepDeadlineKey];
    [defaults synchronize];
    LTLog(@"SLEEP timer set for %ld min", (long)minutes);
    [[NSNotificationCenter defaultCenter] postNotificationName:LTSleepTimerDidChangeNotification object:self];
}

- (void)cancel {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLTSleepDeadlineKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    LTLog(@"SLEEP timer cancelled");
    [[NSNotificationCenter defaultCenter] postNotificationName:LTSleepTimerDidChangeNotification object:self];
}

// Fires the pause once the deadline passes, then clears itself so a later
// relaunch does not pause again.
- (void)checkExpired {
    NSDate *deadline = [self deadline];
    if (!deadline) return;
    if ([deadline timeIntervalSinceNow] > 0.0) return;
    LTLog(@"SLEEP timer fired, pausing");
    [self cancel];
    [[LTPlayerController sharedController] pausePlayback];
}

@end