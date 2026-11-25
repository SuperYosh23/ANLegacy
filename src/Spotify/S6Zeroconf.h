#import <Foundation/Foundation.h>

extern NSString * const S6ZeroconfDidChangeNotification;   // on the main thread: status changed, a login arrived

// Logging in without typing a password: this device announces itself on the Wi-Fi as a Spotify Connect speaker
// (Bonjour "_spotify-connect._tcp" and a small HTTP server). When the user picks it in the Spotify app on their phone,
// the app sends the account's credentials encrypted for this device (Diffie-Hellman), and the session logs in with them.
@interface S6Zeroconf : NSObject

+ (instancetype)shared;

- (void)start;     // main thread
- (void)stop;

@property (atomic, readonly) BOOL running;
@property (atomic, readonly) uint16_t port;
@property (atomic, readonly, copy) NSString *lastEvent;   // for the login screen and the log

@end
