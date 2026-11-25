#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, S6SessionState) {
    S6SessionStateLoggedOut = 0,   // no account on the device: the login screen shows
    S6SessionStateConnecting,
    S6SessionStateReady,
    S6SessionStateOffline,         // logged in before, Spotify cannot be reached now (tries again by itself)
    S6SessionStateFailed,          // Spotify refused the login (lastError says why)
};

extern NSString * const S6SessionStateDidChangeNotification;   // on the main thread

// The connection to Spotify's access point as the logged-in user: login with the credentials Spotify handed out
// (kept in the keychain), keep-alive, reconnecting, the user's product (Premium) and country, the keys of audio files,
// and Mercury requests. Blocking calls must not run on the main thread.
@interface S6Session : NSObject

+ (instancetype)shared;

@property (atomic, readonly) S6SessionState state;
@property (atomic, readonly, strong) NSError *lastError;
@property (atomic, readonly, copy) NSString *username;
@property (atomic, readonly, copy) NSString *country;           // "CZ"
@property (atomic, readonly, copy) NSDictionary *attributes;    // the product info ("type" = "premium", "image-url"...)
@property (atomic, readonly, copy) NSString *spclientHost;      // "gew1-spclient.spotify.com:443"
@property (atomic, readonly, copy) NSString *dealerHost;        // "gew1-dealer.spotify.com:443" (Spotify Connect's push channel)
@property (nonatomic, readonly) BOOL premium;

- (void)start;                                                 // logs in with the stored account, if there is one
- (void)loginWithUsername:(NSString *)username authType:(NSInteger)authType authData:(NSData *)authData;   // zeroconf
- (void)logout;
- (void)reconnectSoon;                                         // e.g. back from the background

// Waits (up to `timeout`) until the session is ready; NO with the reason otherwise
- (BOOL)waitUntilReady:(NSTimeInterval)timeout error:(NSError **)error;

// The 16-byte AES key of an audio file (blocking; a few tries)
- (NSData *)audioKeyForTrack:(NSData *)gid file:(NSData *)fileId error:(NSError **)error;
// A Mercury GET (hm://...): the reply's payload parts (blocking)
- (NSArray *)mercuryGet:(NSString *)uri status:(NSInteger *)status error:(NSError **)error;

- (NSString *)debugState;
- (void)debugHandshakeTest;     // logs whether the access point handshake works (a made-up login must be refused)

@end
