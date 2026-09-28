#import <Foundation/Foundation.h>

// Home Screen icon revisions.
//
// The bundle ships loose PNGs at every size slot, which is how iOS 6, 7-10 and
// 11+ each pick their own artwork. Current iOS no longer honours those slots for
// the primary icon - it falls back to the iOS 6 57pt file - so the only way to
// put the modern artwork on a recent device is the alternate-icon API. That API
// arrived in iOS 10.3 and always raises a system alert when it changes anything.
@interface LTAppIcon : NSObject

// Alternate icon names declared in Info.plist. A nil/empty name means the
// primary icon, which on modern iOS renders the classic iOS 6 artwork.
+ (NSString *)classicIconName;   // nil
+ (NSString *)roundedIconName;   // Icon7
+ (NSString *)modernIconName;    // Icon11

// True on iOS 11+, where the picker is meaningful. The API itself is 10.3+, but
// 10.3-10.x devices resolve the primary icon fine, so there is nothing to offer
// there.
+ (BOOL)isPickerSupported;

// The icon currently in effect: the user's explicit choice if they made one,
// otherwise whatever iOS reports. nil means the primary/classic icon.
+ (NSString *)currentIconName;

// Human-readable name for the current choice, for the settings row.
+ (NSString *)currentIconLabel;

// Applies an icon by name (nil for the primary). Records the choice so the
// one-shot default in +applyModernIconIfNeeded never overrides it.
+ (void)applyIconNamed:(NSString *)iconName;

// First-run default: move to the modern icon once, unless the user has already
// chosen. Never overrides a deliberate choice, and never runs twice.
+ (void)applyModernIconIfNeeded;

@end
