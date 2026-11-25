#import <Foundation/Foundation.h>

extern NSString * const S6ClientId;            // librespot's ("keymaster") client id
extern NSString * const S6UserAgent;           // as librespot introduces itself to Spotify's web services

// A blocking HTTPS request for Spotify's services (worker threads only): the body, the status and the headers
NSData *S6SyncRequest(NSString *method, NSString *url, NSDictionary *headers, NSData *body, NSInteger *status,
                      NSDictionary **responseHeaders, NSError **error);

// The tokens Spotify's web services want, each fetched when needed and kept until shortly before it expires:
//   - the client token (identifies the app; "client-token" header),
//   - the access token of the logged-in user from login5 (spclient, "Authorization: Bearer"),
//   - a token for the public Web API (api.spotify.com) with the scopes the app uses.
// Blocking; worker threads only.
@interface S6Tokens : NSObject

+ (instancetype)shared;

- (NSString *)clientTokenWithError:(NSError **)error;
- (NSString *)accessTokenWithError:(NSError **)error;
- (NSString *)webTokenWithError:(NSError **)error;

- (void)invalidateAccessToken;     // after a 401
- (void)invalidateWebToken;
- (void)reset;                     // logged out

- (NSString *)debugState;
- (void)debugTokenTest;            // logs which client ids get tokens and how the Web API answers them

@end
