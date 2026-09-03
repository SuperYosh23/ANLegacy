#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Phone-to-phone synchronous library sync over Bluetooth / ad-hoc WiFi using a
// peer-to-peer GameKit GKSession (no LAN server, no manual IP entry). Either
// phone taps "Sync with Another Phone" and the two discover each other and
// merge their full library state (playlists, library, recents, stats).
@interface LTP2PSync : NSObject

+ (BOOL)isSyncing;

// Begins advertising and listening for another phone. Shows its own progress
// alerts and a result alert when done.
+ (void)beginFromViewController:(UIViewController *)presenter;

@end
