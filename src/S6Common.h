// Shared macros and constants. Everything here must be iOS 6.0 safe.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Any API newer than the iOS 6.0 deployment target is a hard error in files that include this header.
#pragma clang diagnostic error "-Wunguarded-availability"

#define L(key) NSLocalizedString((key), nil)
#define S6IsPad() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define S6Log(fmt, ...) NSLog((@"[Sixify] " fmt), ##__VA_ARGS__)

// Runs a block on the main thread (immediately if already there).
static inline void S6Main(dispatch_block_t block)
{
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

extern NSString * const S6ErrorDomain;
extern NSString * const S6ThemeDidChangeNotification;
extern NSString * const S6SettingsDidChangeNotification;
extern NSString * const S6LibraryDidChangeNotification;     // liked songs, saved albums, followed artists or playlists changed

// NSError codes in S6ErrorDomain (HTTP errors use the HTTP status as code)
enum {
    S6ErrorNetwork        = -1,
    S6ErrorTLS            = -2,
    S6ErrorCertificate    = -3,
    S6ErrorTimeout        = -4,
    S6ErrorCancelled      = -5,
    S6ErrorBadResponse    = -6,
    S6ErrorDNS            = -7,
    S6ErrorConnect        = -8,
    S6ErrorConnectionLost = -9,
    S6ErrorAPI            = -10,   // Spotify answered, but with an error
    S6ErrorNotLoggedIn    = -11,   // no Spotify account on the device yet
    S6ErrorAuth           = -12,   // Spotify refused the login (bad credentials, Premium required...)
    S6ErrorRestricted     = -13,   // not available in this country, removed...
    S6ErrorPlayback       = -14,   // the audio could not be fetched, decrypted or decoded
};

NSError *S6MakeError(NSInteger code, NSString *message);

// JSON values as the type the caller expects, nil/0 for anything else (NSNull, wrong type)
NSString *S6Str(id value);         // numbers become their decimal string
NSDictionary *S6Dict(id value);
NSArray *S6Arr(id value);
NSInteger S6Int(id value);
double S6Dbl(id value);
BOOL S6Bool(id value);

// "2026-10-02T17:31:00Z" and "2026-10-02T17:31:05.042684Z"
NSDate *S6DateFromISO(NSString *string);
