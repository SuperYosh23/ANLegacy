#import <Foundation/Foundation.h>

// Scrobbles through ListenBrainz's Last.fm-compatible API. The compat endpoint
// accepts any api_key and ignores api_sig, so no app registration or secret is
// needed — only the user's ListenBrainz session, obtained once via the browser
// approval page.
//
// Call +sharedScrobbler; it self-registers for playback notifications and
// restores any saved session.
@interface LTListenBrainzScrobbler : NSObject

+ (instancetype)sharedScrobbler;

@property (nonatomic, copy, readonly) NSString *sessionKey;
@property (nonatomic, copy, readonly) NSString *username;
@property (nonatomic, readonly) BOOL isConnected;   // has a ListenBrainz session

// Auth flow
- (void)requestTokenWithCompletion:(void (^)(NSString *token, NSError *error))completion;
- (NSURL *)authorizationURLForToken:(NSString *)token;
- (void)fetchSessionForToken:(NSString *)token completion:(void (^)(BOOL ok, NSError *error))completion;

- (void)disconnect;
- (void)flushPendingScrobbles;

// Playback hooks (called by notification observers automatically)
- (void)handleTrackChange:(NSNotification *)note;

@end
