#import "LTListenBrainzScrobbler.h"
#import "S6HTTP.h"
#import "S6Utils.h"
#import "LTPlayerController.h"
#import "LTModel.h"
#import "LTLog.h"

static NSString *const kSessionKeyKey = @"LTListenBrainzSessionKey";
static NSString *const kUsernameKey = @"LTListenBrainzUsername";
static NSString *const kPendingScrobblesKey = @"LTListenBrainzPendingScrobbles";
static NSString *const kPendingTokenKey = @"LTListenBrainzPendingToken";

// ListenBrainz's Last.fm compat layer does not validate api_key (it relies on
// rate limiting), so a fixed client identifier is all we need. api_sig is
// likewise ignored.
static NSString *const kApiKey = @"legacymusic";
static NSString *const kAPIBaseURL = @"https://listenbrainz.org/2.0/";
static NSString *const kAuthBaseURL = @"https://listenbrainz.org/api/auth/";

@interface LTListenBrainzScrobbler ()
@property (nonatomic, copy) NSString *sessionKey;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, strong) LTTrack *currentTrack;
@property (nonatomic, assign) NSTimeInterval trackStartTime;
@end

@implementation LTListenBrainzScrobbler

+ (instancetype)sharedScrobbler {
    static LTListenBrainzScrobbler *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [[LTListenBrainzScrobbler alloc] init];
        [s loadCredentials];
        [[NSNotificationCenter defaultCenter] addObserver:s
                                                 selector:@selector(handleTrackChange:)
                                                     name:LTPlayerTrackDidChangeNotification
                                                   object:nil];
    });
    return s;
}

- (void)loadCredentials {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.sessionKey = [d stringForKey:kSessionKeyKey] ?: @"";
    self.username = [d stringForKey:kUsernameKey] ?: @"";
}

- (void)saveCredentials {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.sessionKey ?: @"" forKey:kSessionKeyKey];
    [d setObject:self.username ?: @"" forKey:kUsernameKey];
}

- (BOOL)isConnected { return self.sessionKey.length > 0; }

// S6HTTP uses the bundled mbedTLS stack and CA file, so ListenBrainz's modern
// certificate chain also works on iOS 4/5 (whose system trust store does not).
- (void)postMethod:(NSString *)method params:(NSDictionary *)extra completion:(void (^)(NSDictionary *, NSError *))completion {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    [params setObject:method forKey:@"method"];
    [params setObject:kApiKey forKey:@"api_key"];
    [params setObject:@"json" forKey:@"format"];
    if (self.sessionKey.length) [params setObject:self.sessionKey forKey:@"sk"];
    if (extra) [params addEntriesFromDictionary:extra];

    [S6HTTP postForm:kAPIBaseURL fields:params completion:^(id json, NSInteger status, NSError *err) {
        if (err) { if (completion) completion(nil, err); return; }
        NSDictionary *dict = [json isKindOfClass:[NSDictionary class]] ? (NSDictionary *)json : nil;
        if ([dict objectForKey:@"error"]) {
            NSError *e = [NSError errorWithDomain:@"ListenBrainz"
                                            code:[[dict objectForKey:@"error"] integerValue]
                                        userInfo:[NSDictionary dictionaryWithObject:([dict objectForKey:@"message"] ?: @"ListenBrainz error")
                                                                             forKey:NSLocalizedDescriptionKey]];
            if (completion) completion(nil, e);
            return;
        }
        if (completion) completion(dict, nil);
    }];
}

#pragma mark - Auth

- (void)requestTokenWithCompletion:(void (^)(NSString *, NSError *))completion {
    [self postMethod:@"auth.getToken" params:nil completion:^(NSDictionary *json, NSError *err) {
        if (err) { if (completion) completion(nil, err); return; }
        NSString *token = [json objectForKey:@"token"];
        if (completion) completion(token, nil);
    }];
}

- (NSURL *)authorizationURLForToken:(NSString *)token {
    NSString *s = [NSString stringWithFormat:@"%@?api_key=%@&token=%@", kAuthBaseURL, kApiKey, [S6Utils urlEncode:token]];
    return [NSURL URLWithString:s];
}

- (void)fetchSessionForToken:(NSString *)token completion:(void (^)(BOOL, NSError *))completion {
    NSDictionary *p = [NSDictionary dictionaryWithObject:token forKey:@"token"];
    [self postMethod:@"auth.getSession" params:p completion:^(NSDictionary *json, NSError *err) {
        if (err) { if (completion) completion(NO, err); return; }
        NSString *sk = [[json objectForKey:@"session"] objectForKey:@"key"];
        NSString *name = [[json objectForKey:@"session"] objectForKey:@"name"];
        if (sk.length) {
            self.sessionKey = sk;
            if (name.length) self.username = name;
            [self saveCredentials];
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:kPendingTokenKey];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"LTListenBrainzDidChangeNotification" object:self];
            if (completion) completion(YES, nil);
        } else {
            if (completion) completion(NO, [NSError errorWithDomain:@"ListenBrainz" code:2 userInfo:[NSDictionary dictionaryWithObject:@"No session key" forKey:NSLocalizedDescriptionKey]]);
        }
    }];
}

- (void)disconnect {
    self.sessionKey = @"";
    self.username = @"";
    [self saveCredentials];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LTListenBrainzDidChangeNotification" object:self];
}

#pragma mark - Scrobbling

- (void)updateNowPlaying:(LTTrack *)track {
    if (!self.isConnected || !track) return;
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject:track.title ?: @"" forKey:@"track"];
    [p setObject:track.artist ?: @"" forKey:@"artist"];
    if (track.album.length) [p setObject:track.album forKey:@"album"];
    if (track.duration > 0) [p setObject:[NSString stringWithFormat:@"%.0f", track.duration] forKey:@"duration"];
    [self postMethod:@"track.updateNowPlaying" params:p completion:nil];
}

- (NSMutableArray *)pendingScrobbles {
    NSArray *arr = [[NSUserDefaults standardUserDefaults] arrayForKey:kPendingScrobblesKey];
    if (![arr isKindOfClass:[NSArray class]]) arr = [NSArray array];
    return [NSMutableArray arrayWithArray:arr];
}

- (void)savePendingScrobbles:(NSArray *)arr {
    [[NSUserDefaults standardUserDefaults] setObject:arr forKey:kPendingScrobblesKey];
}

- (void)queueScrobbleForTrack:(LTTrack *)track timestamp:(NSTimeInterval)ts {
    if (!track) return;
    if (ts <= 0) ts = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [d setObject:track.title ?: @"" forKey:@"track"];
    [d setObject:track.artist ?: @"" forKey:@"artist"];
    if (track.album.length) [d setObject:track.album forKey:@"album"];
    [d setObject:[NSString stringWithFormat:@"%.0f", ts] forKey:@"timestamp"];
    NSMutableArray *pending = [self pendingScrobbles];
    [pending addObject:d];
    [self savePendingScrobbles:pending];
    LTLog(@"LB queued offline scrobble %@ - %@", track.artist, track.title);
}

- (void)flushPendingScrobbles {
    if (!self.isConnected) return;
    NSArray *pending = [self pendingScrobbles];
    if (!pending.count) return;
    LTLog(@"LB flushing %lu pending scrobbles", (unsigned long)pending.count);
    NSMutableArray *remaining = [NSMutableArray array];
    for (NSDictionary *d in pending) {
        __block BOOL done = NO;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [self postMethod:@"track.scrobble" params:[d mutableCopy] completion:^(NSDictionary *json, NSError *err) {
            if (err) { [remaining addObject:d]; LTLog(@"LB flush fail: %@", err); }
            else LTLog(@"LB flushed %@ - %@", [d objectForKey:@"artist"], [d objectForKey:@"track"]);
            done = YES;
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    }
    [self savePendingScrobbles:remaining];
}

- (void)scrobbleTrack:(LTTrack *)track timestamp:(NSTimeInterval)ts {
    if (!self.isConnected || !track) return;
    if (ts <= 0) ts = [[NSDate date] timeIntervalSince1970];
    [self flushPendingScrobbles];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    [p setObject:track.title ?: @"" forKey:@"track"];
    [p setObject:track.artist ?: @"" forKey:@"artist"];
    if (track.album.length) [p setObject:track.album forKey:@"album"];
    [p setObject:[NSString stringWithFormat:@"%.0f", ts] forKey:@"timestamp"];
    [self postMethod:@"track.scrobble" params:p completion:^(NSDictionary *json, NSError *err) {
        if (err) {
            LTLog(@"LB scrobble error: %@ (queuing)", err);
            [self queueScrobbleForTrack:track timestamp:ts];
        } else {
            LTLog(@"LB scrobbled %@ - %@", track.artist, track.title);
        }
    }];
}

#pragma mark - Playback hooks

- (void)handleTrackChange:(NSNotification *)note {
    LTPlayerController *pc = [LTPlayerController sharedController];
    [self flushPendingScrobbles];
    // Scrobble the previous track if it played long enough.
    if (self.currentTrack && self.trackStartTime > 0) {
        NSTimeInterval played = [[NSDate date] timeIntervalSince1970] - self.trackStartTime;
        NSTimeInterval dur = self.currentTrack.duration > 0 ? self.currentTrack.duration : 0;
        BOOL enough = played >= 30 && (dur <= 0 || played >= dur * 0.5 || played >= 240);
        if (enough) [self scrobbleTrack:self.currentTrack timestamp:self.trackStartTime];
    }
    LTTrack *t = [pc currentTrack];
    self.currentTrack = t;
    self.trackStartTime = [[NSDate date] timeIntervalSince1970];
    if (t) [self updateNowPlaying:t];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
