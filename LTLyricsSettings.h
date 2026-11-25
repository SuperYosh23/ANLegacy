#import <UIKit/UIKit.h>

// Calibration for synced lyrics.
//
// YouTube's LRC timestamps are frequently offset from the audio by a few
// hundred milliseconds, and the direction is not predictable per track, so this
// is a user-adjustable constant rather than something to auto-detect. Positive
// values move the highlight earlier.
extern NSString * const LTLyricsOffsetKey;

double LTLyricsOffset(void);
void LTSetLyricsOffset(double seconds);