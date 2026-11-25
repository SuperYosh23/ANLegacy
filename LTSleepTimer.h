#import <Foundation/Foundation.h>

// Sleep timer: pauses playback after a chosen delay.
//
// Deliberately counts down wall-clock time rather than track position, so it
// behaves the same for streaming and for local files, and survives buffering. The
// deadline is persisted so an app relaunch does not silently cancel an active
// timer.
@interface LTSleepTimer : NSObject

+ (LTSleepTimer *)shared;

// Minutes from now, or 0 to cancel. The deadline is stored absolute rather than
// as a countdown so it stays correct across a relaunch.
- (void)startWithMinutes:(NSInteger)minutes;
- (void)cancel;

// Minutes left, rounded up; 0 when inactive. Handy for a settings subtitle.
- (NSInteger)remainingMinutes;

// Yes while a timer is running, including after a relaunch.
- (BOOL)isActive;

// NSDate for the deadline, or nil. Exposed so a screen can show a countdown.
- (NSDate *)deadline;

// Posted whenever the timer starts, ends or fires, so open screens can redraw.
extern NSString * const LTSleepTimerDidChangeNotification;

@end