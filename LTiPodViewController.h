#import <UIKit/UIKit.h>

@class LTTrack;

// Full-screen iPod emulator ("iPod mode"). When enabled, the app's root view
// controller becomes an iPod-classic-style interface driven by a virtual click
// wheel. Music comes from the shared library/playlists, and playback reuses the
// shared player controller.
@interface LTiPodViewController : UIViewController

+ (BOOL)isEnabled;
+ (void)setEnabled:(BOOL)enabled;
// Swap the app's root controller to/from the iPod emulator based on isEnabled.
+ (void)applyiPodModeAnimated:(BOOL)animated;

@end