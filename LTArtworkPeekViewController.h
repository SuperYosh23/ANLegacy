#import <UIKit/UIKit.h>

@class LTTrack;

// The card shown when the Now Playing artwork is pressed in.
//
// Purely visual: there is nothing to open on a full press, so UIKit dismisses the
// peek and the player keeps playing untouched.
@interface LTArtworkPeekViewController : UIViewController

// image may be nil, in which case the high-resolution thumbnail for the track is
// fetched and shown once it arrives.
- (instancetype)initWithTrack:(LTTrack *)track image:(UIImage *)image;

@end