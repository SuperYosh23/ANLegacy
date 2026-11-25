#import <UIKit/UIKit.h>

// The album art background: the artwork behind the player and the queue.
//
// It is on unless the user turns it off. The default used to depend on the
// device's OS version - on for the modern themes, off for iOS 6 - but there
// was nothing about the feature that needed a newer system, so the default is
// now the same everywhere.
//
// The value is stored in NSUserDefaults (key "LTPlayerArtworkBackground"). It
// is only written when the user changes it; the default is what is reported
// while nothing has been stored.
@interface LTArtworkBackground : NSObject
+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)enabled;
@end
