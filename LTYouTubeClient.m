#import "LTYouTubeClient.h"
#import "S6JSON.h"
#import "S6HTTPRequest.h"
#import "LTPlaylistStore.h"
#import "LTLog.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

NSString *const LTAPIKey = @"AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";
NSString *const LTBrowserUserAgent = @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

// Narrower than this and the image is YouTube's "missing artwork" placeholder
// (120x90) rather than real cover art. See loadArtworkFromCandidates:.
//
// This was 400, which was right while thumbnails arrived uncropped and their
// width was a fair proxy for size. Centering a video thumbnail to a square
// takes a 480x360 still down to 360x360, and 360 < 400, so every video's own
// artwork began being rejected as a placeholder and album and artist rows -
// which fall back to the first track's thumbnail - went blank. The floor has to
// separate YouTube's 120x90 from real art, nothing more; 200 does that with
// room to spare.
const NSInteger kMinUsableArtworkWidth = 200;

NSString *const LTYouTubeDomain = @"LTYouTube";

static id LTPath(id root, id key, ...) {
    if (!root) return nil;
    id current = root;
    va_list args;
    va_start(args, key);
    for (id k = key; k != nil; k = va_arg(args, id)) {
        if ([current isKindOfClass:[NSDictionary class]]) {
            current = [current objectForKey:k];
        } else if ([current isKindOfClass:[NSArray class]]) {
            NSInteger idx = [k respondsToSelector:@selector(intValue)] ? [k intValue] : -1;
            if (idx < 0 || idx >= (NSInteger)[(NSArray *)current count]) { current = nil; break; }
            current = [current objectAtIndex:(NSUInteger)idx];
        } else {
            current = nil;
            break;
        }
    }
    va_end(args);
    return current;
}

// Bounded depth-first search for the first occurrence of a key anywhere in a
// parsed JSON tree.
//
// The InnerTube responses reach these values through deeply nested renderer
// chains whose exact shape changes without notice, so a hardcoded key path would
// be the first thing to break. Depth is capped both because the useful values sit
// near the top and because this has to stay cheap on a 3GS.
static id LTFindFirstValue(id root, NSString *key, NSInteger depth) {
    if (depth <= 0 || !root) return nil;
    if ([root isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = root;
        id direct = [dict objectForKey:key];
        if (direct) return direct;
        for (id sub in [dict allValues]) {
            id found = LTFindFirstValue(sub, key, depth - 1);
            if (found) return found;
        }
    } else if ([root isKindOfClass:[NSArray class]]) {
        for (id sub in (NSArray *)root) {
            id found = LTFindFirstValue(sub, key, depth - 1);
            if (found) return found;
        }
    }
    return nil;
}

// YouTube returns counts as strings ("19475837"), not numbers, so they are
// reduced here for display.
static NSString *LTFormatCount(id raw) {
    if (![raw isKindOfClass:[NSString class]]) {
        if ([raw respondsToSelector:@selector(stringValue)]) raw = [raw stringValue];
        else return nil;
    }
    NSString *digits = [[(NSString *)raw stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (!digits.length) return nil;
    NSCharacterSet *nonNumeric = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    digits = [digits stringByReplacingOccurrencesOfString:@"," withString:@""];
    if ([digits rangeOfCharacterFromSet:nonNumeric].location != NSNotFound) {
        return nil;
    }
    unsigned long long n = [digits longLongValue];
    if (n >= 1000000000ULL) return [NSString stringWithFormat:@"%.2fB", n / 1000000000.0];
    if (n >= 1000000ULL)    return [NSString stringWithFormat:@"%.1fM", n / 1000000.0];
    if (n >= 1000ULL)       return [NSString stringWithFormat:@"%.1fK", n / 1000.0];
    return [NSString stringWithFormat:@"%llu", n];
}

// Inverse of LTFormatCount: reads back a count token YouTube formatted for
// display, so a song's "1.2B plays" becomes 1200000000 and can be sorted.
// Returns -1 for a token it cannot read, which is deliberately distinct from a
// real zero.
static long long LTParseCountToken(NSString *token) {
    if (![token isKindOfClass:[NSString class]]) return -1;
    token = [token stringByReplacingOccurrencesOfString:@"," withString:@""];
    token = [token stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!token.length) return -1;

    double multiplier = 1.0;
    unichar last = [token characterAtIndex:token.length - 1];
    if (last == 'K' || last == 'k') { multiplier = 1e3; token = [token substringToIndex:token.length - 1]; }
    else if (last == 'M' || last == 'm') { multiplier = 1e6; token = [token substringToIndex:token.length - 1]; }
    else if (last == 'B' || last == 'b') { multiplier = 1e9; token = [token substringToIndex:token.length - 1]; }

    NSCharacterSet *nonNumeric = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([token rangeOfCharacterFromSet:nonNumeric].location != NSNotFound) return -1;
    if (!token.length) return -1;
    return (long long)([token doubleValue] * multiplier);
}

static NSString *LTRunText(id node) {
    if (![node isKindOfClass:[NSDictionary class]]) return nil;
    NSString *simple = [node objectForKey:@"simpleText"];
    if ([simple isKindOfClass:[NSString class]] && simple.length) return simple;
    NSArray *runs = [node objectForKey:@"runs"];
    if ([runs isKindOfClass:[NSArray class]]) {
        NSMutableString *out = [NSMutableString string];
        for (NSDictionary *run in runs) {
            NSString *t = [run objectForKey:@"text"];
            if ([t isKindOfClass:[NSString class]]) [out appendString:t];
        }
        if (out.length) return out;
    }
    return nil;
}


@interface LTYouTubeClient ()
@property (nonatomic, strong) NSCache *imageCache;
@property (nonatomic, strong) NSMutableDictionary *channelAvatarCache;
@property (nonatomic, strong) NSMutableDictionary *pendingChannelAvatars;
@property (nonatomic, strong) NSMutableDictionary *pendingNameAvatars;
// General-page metadata is immutable per video. Caching it means reopening the
// page, or replaying a track, never pays for another round of InnerTube calls.
@property (nonatomic, strong) NSCache *generalInfoCache;
// A client that answers LOGIN_REQUIRED / "not a bot" stays blocked for a short
// while. Retrying it on every track was adding a slow, always-failing attempt to
// the front of the General-page client chain.
@property (nonatomic, strong) NSMutableDictionary *blockedPlayerClients;
@end

// Bounded so one tap cannot turn into an unbounded crawl of a prolific
// artist's discography. Four continuation requests on top of the first page is
// roughly a couple of hundred songs.
static const NSInteger kLTArtistSongPages = 4;

@implementation LTYouTubeClient

+ (instancetype)sharedClient {
    static LTYouTubeClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[LTYouTubeClient alloc] init];
    });
    return shared;
}

- (id)init {
    self = [super init];
    if (self) {
        // Artwork is decoded to full RGBA, so a single 1200x1200 entry is
        // ~5.7MB. Unbounded, the cache is exactly the wrong thing to have on a
        // 256MB 3GS: the OS purges it under pressure and every cell then pays
        // for a synchronous decode from disk again. Budget it in pixels rather
        // than entries so one huge image cannot quietly dominate.
        _imageCache = [[NSCache alloc] init];
        _imageCache.totalCostLimit = 12 * 1024 * 1024;
        _channelAvatarCache = [NSMutableDictionary dictionary];
        _pendingChannelAvatars = [NSMutableDictionary dictionary];
        _pendingNameAvatars = [NSMutableDictionary dictionary];
        // Small, bounded caches: these entries are a few hundred bytes each and
        // the 3GS only has 256MB.
        _generalInfoCache = [[NSCache alloc] init];
        _generalInfoCache.countLimit = 24;
        _blockedPlayerClients = [NSMutableDictionary dictionary];
    }
    return self;
}

// Bot-blocked client contexts do not recover within a single listening session.
// Skip them briefly instead of paying for another doomed handshake per track.
- (BOOL)isPlayerClientBlocked:(NSString *)name {
    NSDate *until = [self.blockedPlayerClients objectForKey:name];
    return until != nil && [until timeIntervalSinceNow] > 0;
}

- (void)markPlayerClientBlocked:(NSString *)name {
    if (!name.length) return;
    [self.blockedPlayerClients setObject:[NSDate dateWithTimeIntervalSinceNow:120.0] forKey:name];
}

#pragma mark - Networking

static BOOL LTShouldUseMbedTLS(void) {
    // iOS 6.x system TLS (SecureTransport) often cannot negotiate with modern
    // YouTube/Google endpoints (ciphers/SNI), causing timeouts. Use mbedTLS with
    // the bundled CA store there for compatibility.
    return ([[[UIDevice currentDevice] systemVersion] floatValue] < 7.0f);
}

static void LTDeliverAsyncRequestResult(NSOperationQueue *queue, void (^completionHandler)(NSURLResponse *, NSData *, NSError *),
                                        NSURLResponse *response, NSData *data, NSError *error) {
    if (!completionHandler) return;
    void (^block)(void) = ^{
        completionHandler(response, data, error);
    };
    if (queue) {
        [queue addOperationWithBlock:block];
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

static void LTSendAsyncRequest(NSURLRequest *request, NSOperationQueue *queue, void (^completionHandler)(NSURLResponse *, NSData *, NSError *)) {
    if (!completionHandler) return;

    // Prefer mbedTLS on old iOS for HTTPS reliability against modern endpoints.
    if (LTShouldUseMbedTLS() && [[request.URL.scheme lowercaseString] isEqualToString:@"https"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                S6HTTPRequest *r = [[S6HTTPRequest alloc] initWithMethod:(request.HTTPMethod.length ? request.HTTPMethod : @"GET")
                                                                      URL:request.URL];
                NSDictionary *hdrs = [request allHTTPHeaderFields];
                if (hdrs.count) r.headers = hdrs;
                if (request.HTTPBody.length) r.body = request.HTTPBody;
                NSTimeInterval t = [request timeoutInterval];
                if (t > 0) r.readTimeout = t;
                // The old 20s connect budget let a dead endpoint hold up a whole
                // chain of sequential client attempts. Keep it below the read
                // timeout so one failed client cannot eat the whole tab budget.
                r.connectTimeout = 5;
                __block NSError *failure = nil;
                r.onComplete = ^(NSError *e) { failure = e; };
                [r runSynchronously];
                NSData *data = r.responseBody ?: [NSData data];
                NSURLResponse *response = nil;
                if (!failure) {
                    // NSHTTPURLResponse's statusCode initializer is iOS 5+.
                    if ([NSHTTPURLResponse instancesRespondToSelector:@selector(initWithURL:statusCode:HTTPVersion:headerFields:)]) {
                        response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                               statusCode:r.statusCode
                                                              HTTPVersion:@"HTTP/1.1"
                                                             headerFields:r.responseHeaders];
                    } else {
                        response = [[NSURLResponse alloc] initWithURL:request.URL
                                                             MIMEType:@"application/json"
                                                expectedContentLength:(NSInteger)[data length]
                                                     textEncodingName:@"utf-8"];
                    }
                }
                LTDeliverAsyncRequestResult(queue, completionHandler, response, failure ? nil : data, failure);
            }
        });
        return;
    }

    if ([NSURLConnection respondsToSelector:@selector(sendAsynchronousRequest:queue:completionHandler:)]) {
        [NSURLConnection sendAsynchronousRequest:request queue:queue completionHandler:completionHandler];
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURLResponse *response = nil;
        NSError *error = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
        LTDeliverAsyncRequestResult(queue, completionHandler, response, data, error);
    });
}

// Queue that delivers raw API responses off the main thread, so the JSON parse in
// the completions below is not main-thread work. A private operation queue
// rather than nil, which -sendAsynchronousRequest: marks nonnull.
static NSOperationQueue *LTNetworkCallbackQueue(void) {
    static NSOperationQueue *queue = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 4;
        queue.name = @"com.legacymusic.network";
    });
    return queue;
}

- (void)postToHost:(NSString *)host path:(NSString *)path body:(NSDictionary *)body
        completion:(void (^)(id json, NSError *error))completion {
    [self postToHost:host path:path body:body ingestingVisitorData:YES completion:completion];
}

// ingestingVisitorData must be NO for any request whose client differs from the
// one the cached visitorData came from.
//
// The visitor token is issued per client, so a reply from the WEB client hands
// back a token that is meaningless to the Android VR client. Harvesting it anyway
// used to poison the shared cache: one comments fetch would swap the token, and
// the following VR -player or -next request would go out carrying a WEB token and
// come back empty, which surfaced as "No video information returned" on an
// unrelated page.
- (void)postToHost:(NSString *)host path:(NSString *)path body:(NSDictionary *)body
ingestingVisitorData:(BOOL)ingest completion:(void (^)(id json, NSError *error))completion {
    NSString *urlString = [NSString stringWithFormat:@"https://%@/youtubei/v1/%@?key=%@&prettyPrint=false",
                           host, path, LTAPIKey];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:[NSString stringWithFormat:@"https://%@/", host] forHTTPHeaderField:@"Referer"];

    NSError *serializeError = nil;
    NSData *payload = [S6JSON dataWithObject:body error:&serializeError];
    if (!payload) {
        if (completion) completion(nil, serializeError);
        return;
    }
    [request setHTTPBody:payload];

    LTSendAsyncRequest(request, LTNetworkCallbackQueue(),^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, connectionError); });
            return;
        }
        // Parse off the main thread. A YouTube InnerTube search response is
        // routinely several hundred KB, and NSJSONSerialization on iOS 6 is a
        // slow recursive-descent parser allocating a container per value; this
        // ran on the main thread for every search, browse and lyrics fetch.
        dispatch_async(LTJSONQueue(), ^{
            @autoreleasepool {
                NSError *parseError = nil;
                id obj = [S6JSON objectWithData:data error:&parseError];
                // Everything that touches app state or UI comes back to main.
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!obj) {
                        if (completion) completion(nil, parseError);
                        return;
                    }
                    if (ingest) [self ingestVisitorData:obj];
                    if (completion) completion(obj, nil);
                });
            }
        });
    });
}

- (void)ingestVisitorData:(id)json {
    if (![json isKindOfClass:[NSDictionary class]]) return;
    id vd = LTPath(json, @"responseContext", @"visitorData", nil);
    if ([vd isKindOfClass:[NSString class]] && [(NSString *)vd length]) {
        NSString *decoded = [(NSString *)vd stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (decoded.length) self.visitorData = decoded;
    }
}

#pragma mark - Contexts

- (NSDictionary *)webRemixContext {
    return @{
        @"client": @{
            @"clientName": @"WEB_REMIX",
            @"clientVersion": @"1.20250721.00.00",
            @"gl": @"US",
            @"hl": @"en",
        }
    };
}

- (NSDictionary *)androidVRContext {
    NSMutableDictionary *client = [NSMutableDictionary dictionaryWithDictionary:@{
        @"clientName": @"ANDROID_VR",
        @"clientVersion": @"1.65.10",
        @"gl": @"US",
        @"hl": @"en",
        @"deviceMake": @"Oculus",
        @"deviceModel": @"Quest 3",
        @"androidSdkVersion": @32,
        @"osName": @"Android",
        @"osVersion": @"12L",
        @"userAgent": @"com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
    }];
    if (self.visitorData.length) {
        [client setObject:self.visitorData forKey:@"visitorData"];
    }
    return @{@"client": client};
}

- (NSDictionary *)iosContext {
    NSMutableDictionary *client = [NSMutableDictionary dictionaryWithDictionary:@{
        @"clientName": @"IOS",
        @"clientVersion": @"21.26.4",
        @"gl": @"US",
        @"hl": @"en",
        @"deviceMake": @"Apple",
        @"deviceModel": @"iPhone16,2",
        @"osName": @"iPhone",
        @"osVersion": @"18.3.2.22D82",
        @"userAgent": @"com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
    }];
    if (self.visitorData.length) {
        [client setObject:self.visitorData forKey:@"visitorData"];
    }
    return @{@"client": client};
}

- (NSDictionary *)androidContext {
    NSMutableDictionary *client = [NSMutableDictionary dictionaryWithDictionary:@{
        @"clientName": @"ANDROID",
        @"clientVersion": @"21.26.364",
        @"gl": @"US",
        @"hl": @"en",
        @"androidSdkVersion": @30,
        @"osName": @"Android",
        @"osVersion": @"11",
        @"userAgent": @"com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip",
    }];
    if (self.visitorData.length) {
        [client setObject:self.visitorData forKey:@"visitorData"];
    }
    return @{@"client": client};
}

// The mobile music client is required for timed (synced) lyric responses.
- (NSDictionary *)androidMusicContext {
    NSMutableDictionary *client = [NSMutableDictionary dictionaryWithDictionary:@{
        @"clientName": @"ANDROID_MUSIC",
        @"clientVersion": @"7.21.50",
        @"gl": @"US",
        @"hl": @"en",
        @"androidSdkVersion": @30,
        @"osName": @"Android",
        @"osVersion": @"11",
        @"userAgent": @"com.google.android.apps.youtube.music/7.21.50 (Linux; U; Android 11) gzip",
    }];
    if (self.visitorData.length) {
        [client setObject:self.visitorData forKey:@"visitorData"];
    }
    return @{@"client": client};
}

#pragma mark - Search

+ (NSString *)searchParamsForType:(NSString *)type {
    static NSDictionary *params = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        params = @{
            @"songs": @"EgWKAQIIAWoMEA4QChADEAQQCRAF",
            @"videos": @"EgWKAQIQAWoMEA4QChADEAQQCRAF",
            @"albums": @"EgWKAQIYAWoMEA4QChADEAQQCRAF",
            @"artists": @"EgWKAQIgAWoMEA4QChADEAQQCRAF",
            @"playlists": @"Eg-KAQwIABAAGAAgACgBMABqChAEEAMQCRAFEAo=",
        };
    });
    return [params objectForKey:type];
}

- (void)searchWithQuery:(NSString *)query type:(NSString *)type
             completion:(void (^)(NSArray *items, NSError *error))completion {
    if (!query.length) {
        if (completion) completion(nil, [self errorWithCode:1 message:@"Empty search"]);
        return;
    }
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
        @"context": [self webRemixContext],
        @"query": query,
    }];
    NSString *p = [[self class] searchParamsForType:type];
    if (p.length) [body setObject:p forKey:@"params"];

    [self postToHost:@"music.youtube.com" path:@"search" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            if (completion) completion(nil, error);
            return;
        }
        NSArray *items = [self parseSearchResults:json];
        if (completion) completion(items, nil);
    }];
}

- (BOOL)arrayContainsVideoId:(NSArray *)arr videoId:(NSString *)vid {
    for (LTTrack *t in arr) {
        if ([t.videoId isEqualToString:vid]) return YES;
    }
    return NO;
}

- (void)extractRadioTracksFromContents:(NSArray *)contents intoArray:(NSMutableArray *)tracks excludeVideoId:(NSString *)exclude {
    if (![contents isKindOfClass:[NSArray class]]) return;
    for (id c in contents) {
        if (![c isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *ppr = [c objectForKey:@"playlistPanelVideoRenderer"];
        if (ppr) {
            LTTrack *t = [self trackFromPlaylistPanelVideoRenderer:ppr];
            if (t && ![t.videoId isEqualToString:exclude] && ![self arrayContainsVideoId:tracks videoId:t.videoId]) [tracks addObject:t];
        }
    }
}

- (LTTrack *)trackFromPlaylistPanelVideoRenderer:(NSDictionary *)r {
    NSString *videoId = [r objectForKey:@"videoId"];
    if (![videoId isKindOfClass:[NSString class]] || !videoId.length) return nil;
    LTTrack *t = [[LTTrack alloc] init];
    t.videoId = videoId;
    NSArray *truns = LTPath(r, @"title", @"runs", nil);
    if ([truns isKindOfClass:[NSArray class]]) {
        t.title = [self textFromRuns:truns];
    } else {
        t.title = LTPath(r, @"title", @"simpleText", nil);
    }
    if (!t.title.length && [[r objectForKey:@"title"] isKindOfClass:[NSString class]]) t.title = [r objectForKey:@"title"];
    NSArray *byline = LTPath(r, @"longBylineText", @"runs", nil);
    if ([byline isKindOfClass:[NSArray class]] && byline.count) {
        NSArray *f = [self filteredRuns:byline];
        if (f.count) t.artist = [f objectAtIndex:0];
    }
    t.thumbnailURL = [self videoThumbnailURL:r];
    NSString *len = LTPath(r, @"lengthText", @"simpleText", nil);
    if (!len) len = LTPath(r, @"lengthText", @"runs", @0, @"text", nil);
    if ([len isKindOfClass:[NSString class]] && len.length) t.duration = [[self class] timeFromString:len];
    return t;
}

- (void)fetchRadioForTrack:(LTTrack *)track completion:(void (^)(NSArray *tracks, NSError *error))completion {
    if (!track.videoId.length) {
        if (completion) completion(nil, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    NSDictionary *body = @{
        @"context": [self webRemixContext],
        @"enablePersistentPlaylistPanel": @YES,
        @"isAudioOnly": @YES,
        @"tunerSettingValue": @"AUTOMIX_SETTING_NORMAL",
        @"videoId": track.videoId,
        @"playlistId": [NSString stringWithFormat:@"RDAMVM%@", track.videoId],
        @"watchEndpointMusicSupportedConfigs": @{
            @"watchEndpointMusicConfig": @{
                @"hasPersistentPlaylistPanel": @YES,
                @"musicVideoType": @"MUSIC_VIDEO_TYPE_ATV",
            }
        },
    };
    [self postToHost:@"music.youtube.com" path:@"next" body:body completion:^(id json, NSError *error) {
        if (error || ![json isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(nil, error);
            return;
        }
        NSMutableArray *tracks = [NSMutableArray array];
        NSArray *tabs = LTPath(json, @"contents", @"singleColumnMusicWatchNextResultsRenderer", @"tabbedRenderer", @"watchNextTabbedResultsRenderer", @"tabs", nil);
        if ([tabs isKindOfClass:[NSArray class]]) {
            for (id tab in tabs) {
                NSDictionary *tabRenderer = [tab objectForKey:@"tabRenderer"];
                if (![tabRenderer isKindOfClass:[NSDictionary class]]) continue;
                NSArray *contents = LTPath(tabRenderer, @"content", @"tabRendererContent", @"listPanelRenderer", @"contents", nil);
                if (![contents isKindOfClass:[NSArray class]]) {
                    contents = LTPath(tabRenderer, @"content", @"sectionListRenderer", @"contents", nil);
                }
                [self extractRadioTracksFromContents:contents intoArray:tracks excludeVideoId:track.videoId];
                if (tracks.count > 30) break;
            }
        }
        if (!tracks.count) {
            [self enumerateRenderersIn:json key:@"playlistPanelVideoRenderer" block:^(NSDictionary *r) {
                LTTrack *t = [self trackFromPlaylistPanelVideoRenderer:r];
                if (t && ![t.videoId isEqualToString:track.videoId] && ![self arrayContainsVideoId:tracks videoId:t.videoId]) [tracks addObject:t];
            }];
        }
        if (completion) completion(tracks, nil);
    }];
}

- (void)fetchRadioForArtist:(NSString *)artist completion:(void (^)(NSArray *tracks, NSError *error))completion {
    if (!artist.length) {
        if (completion) completion(nil, [self errorWithCode:1 message:@"Missing artist"]);
        return;
    }
    [self searchVideosWithQuery:artist completion:^(NSArray *tracks, NSError *error) {
        if (!tracks.count) {
            if (completion) completion(nil, error);
            return;
        }
        LTTrack *seed = [tracks objectAtIndex:0];
        [self fetchRadioForTrack:seed completion:completion];
    }];
}

- (void)searchVideosWithQuery:(NSString *)query
                   completion:(void (^)(NSArray *tracks, NSError *error))completion {
    if (!query.length) {
        if (completion) completion(nil, [self errorWithCode:1 message:@"Empty search"]);
        return;
    }
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:@{
        @"context": [self webContext],
        @"query": query,
    }];
    NSString *p = [[self class] searchParamsForType:@"videos"];
    if (p.length) [body setObject:p forKey:@"params"];

    [self postToHost:@"www.youtube.com" path:@"search" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            if (completion) completion(nil, error);
            return;
        }
        NSMutableArray *tracks = [NSMutableArray array];
        [self enumerateRenderersIn:json key:@"videoRenderer" block:^(NSDictionary *renderer) {
            LTTrack *track = [self trackFromVideoRenderer:renderer];
            if (track) [tracks addObject:track];
        }];
        if (tracks.count) {
            if (completion) completion(tracks, nil);
            return;
        }
        NSMutableDictionary *fallbackBody = [NSMutableDictionary dictionaryWithDictionary:@{
            @"context": [self androidContext],
            @"query": query,
        }];
        if (p.length) [fallbackBody setObject:p forKey:@"params"];
        [self postToHost:@"www.youtube.com" path:@"search" body:fallbackBody completion:^(id fallbackJson, NSError *fallbackError) {
            if (fallbackError || !fallbackJson) {
                if (completion) completion(tracks, nil);
                return;
            }
            [self enumerateRenderersIn:fallbackJson key:@"compactVideoRenderer" block:^(NSDictionary *renderer) {
                LTTrack *track = [self trackFromCompactVideoRenderer:renderer];
                if (track) [tracks addObject:track];
            }];
            if (completion) completion(tracks, nil);
        }];
    }];
}

- (NSDictionary *)webContext {
    return @{
        @"client": @{
            @"clientName": @"WEB",
            @"clientVersion": @"2.20241112.00.00",
            @"gl": @"US",
            @"hl": @"en",
        }
    };
}

- (LTTrack *)trackFromVideoRenderer:(NSDictionary *)renderer {
    NSString *videoId = [renderer objectForKey:@"videoId"];
    if (![videoId isKindOfClass:[NSString class]] || !videoId.length) return nil;
    id titleObj = [renderer objectForKey:@"title"];
    NSString *title = [self textFromRuns:[titleObj objectForKey:@"runs"]];
    if (!title.length) title = [titleObj objectForKey:@"simpleText"];
    if (!title.length) return nil;

    LTTrack *track = [[LTTrack alloc] init];
    track.title = title;
    track.videoId = videoId;
    track.thumbnailURL = [self compatThumbnailURL:[self videoThumbnailURL:renderer] videoId:videoId];
    NSString *lengthText = LTPath(renderer, @"lengthText", @"simpleText", nil);
    if (![lengthText isKindOfClass:[NSString class]]) lengthText = LTPath(renderer, @"lengthText", @"runs", @0, @"text", nil);
    if (lengthText.length) track.duration = [[self class] timeFromString:lengthText];
    NSArray *ownerRuns = LTPath(renderer, @"ownerText", @"runs", nil);
    NSArray *parts = [self filteredRuns:ownerRuns];
    if (parts.count) track.artist = [parts objectAtIndex:0];
    return track;
}

- (LTTrack *)trackFromCompactVideoRenderer:(NSDictionary *)renderer {
    NSString *videoId = [renderer objectForKey:@"videoId"];
    if (![videoId isKindOfClass:[NSString class]] || !videoId.length) return nil;
    id titleObj = [renderer objectForKey:@"title"];
    NSString *title = [self textFromRuns:[titleObj objectForKey:@"runs"]];
    if (!title.length) title = [titleObj objectForKey:@"simpleText"];
    if (!title.length) return nil;

    LTTrack *track = [[LTTrack alloc] init];
    track.title = title;
    track.videoId = videoId;
    track.thumbnailURL = [self compatThumbnailURL:[self videoThumbnailURL:renderer] videoId:videoId];
    NSString *lengthText = LTPath(renderer, @"lengthText", @"simpleText", nil);
    if (![lengthText isKindOfClass:[NSString class]]) lengthText = LTPath(renderer, @"lengthText", @"runs", @0, @"text", nil);
    if (lengthText.length) track.duration = [[self class] timeFromString:lengthText];
    NSArray *bylineRuns = LTPath(renderer, @"longBylineText", @"runs", nil);
    NSArray *parts = [self filteredRuns:bylineRuns];
    if (!parts.count) parts = [self filteredRuns:LTPath(renderer, @"shortBylineText", @"runs", nil)];
    if (parts.count) track.artist = [parts objectAtIndex:0];
    return track;
}

- (NSString *)videoThumbnailURL:(NSDictionary *)renderer {
    NSArray *thumbs = LTPath(renderer, @"thumbnail", @"thumbnails", nil);
    return [self largestThumbnailURLFromArray:thumbs];
}

- (NSArray *)parseSearchResults:(NSDictionary *)json {
    NSArray *sections = LTPath(json, @"contents", @"tabbedSearchResultsRenderer", @"tabs", @0,
                               @"tabRenderer", @"content", @"sectionListRenderer", @"contents", nil);
    NSMutableArray *items = [NSMutableArray array];
    for (id section in sections) {
        if (![section isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *shelf = [section objectForKey:@"musicShelfRenderer"];
        if (!shelf) continue;
        id contents = [shelf objectForKey:@"contents"];
        if (![contents isKindOfClass:[NSArray class]]) continue;
        for (id row in contents) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *item = [row objectForKey:@"musicResponsiveListItemRenderer"];
            if (!item) continue;
            id parsed = [self parseSearchItem:item];
            if (parsed) [items addObject:parsed];
        }
    }
    return items;
}

- (id)parseSearchItem:(NSDictionary *)item {
    NSArray *flex = [item objectForKey:@"flexColumns"];
    if (![flex isKindOfClass:[NSArray class]] || flex.count == 0) return nil;

    NSArray *runs = [self runsFromFlexColumn:[flex objectAtIndex:0]];
    NSString *title = [self textFromRuns:runs];
    if (!title.length) return nil;

    NSDictionary *nav = nil;
    if (runs.count) {
        id firstRun = [runs objectAtIndex:0];
        if ([firstRun isKindOfClass:[NSDictionary class]]) {
            nav = [firstRun objectForKey:@"navigationEndpoint"];
        }
    }
    if (!nav) nav = [item objectForKey:@"navigationEndpoint"];

    NSDictionary *watch = [nav objectForKey:@"watchEndpoint"];
    if (watch) {
        NSString *videoId = [watch objectForKey:@"videoId"];
        if (!videoId.length) {
            videoId = LTPath(item, @"overlay", @"content", @"musicPlayButtonRenderer",
                             @"playNavigationEndpoint", @"watchEndpoint", @"videoId", nil);
        }
        if (!videoId.length) return nil;
        LTTrack *track = [[LTTrack alloc] init];
        track.title = title;
        track.videoId = videoId;
        track.thumbnailURL = [self compatThumbnailURL:[self thumbnailFromItem:item] videoId:videoId];
        NSArray *subRuns = flex.count > 1 ? [self runsFromFlexColumn:[flex objectAtIndex:1]] : nil;
        [self applySubtitleRuns:subRuns toTrack:track];
        return track;
    }

    NSDictionary *browse = [nav objectForKey:@"browseEndpoint"];
    if (browse) {
        NSString *browseId = [browse objectForKey:@"browseId"];
        if (!browseId.length) return nil;
        LTBrowseItem *bi = [[LTBrowseItem alloc] init];
        bi.browseId = browseId;
        bi.title = title;
        bi.kind = [self kindForBrowseId:browseId];
        bi.thumbnailURL = [self thumbnailFromItem:item];
        if (bi.kind == LTBrowseKindArtist) {
            bi.thumbnailURL = [self squareAvatarURL:bi.thumbnailURL size:160];
        }
        NSArray *subRuns = flex.count > 1 ? [self runsFromFlexColumn:[flex objectAtIndex:1]] : nil;
        bi.subtitle = [self textFromRuns:subRuns];
        return bi;
    }
    return nil;
}

#pragma mark - Browse

- (void)browseAlbum:(NSString *)browseId
         completion:(void (^)(NSDictionary *info, NSArray *tracks, NSError *error))completion {
    NSDictionary *body = @{@"context": [self webRemixContext], @"browseId": browseId};
    [self postToHost:@"music.youtube.com" path:@"browse" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            if (completion) completion(nil, nil, error);
            return;
        }
        NSDictionary *info = [self headerInfo:json squareThumbnail:NO];
        NSArray *tracks = [self tracksFromShelf:json];
        if (completion) completion(info, tracks, nil);
    }];
}

- (void)browsePlaylist:(NSString *)browseId
            completion:(void (^)(NSDictionary *info, NSArray *tracks, NSError *error))completion {
    NSDictionary *body = @{@"context": [self webRemixContext], @"browseId": browseId};
    [self postToHost:@"music.youtube.com" path:@"browse" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            if (completion) completion(nil, nil, error);
            return;
        }
        NSDictionary *info = [self headerInfo:json squareThumbnail:NO];
        NSArray *tracks = [self tracksFromPlaylistShelf:json];
        if (completion) completion(info, tracks, nil);
    }];
}

- (void)browseArtist:(NSString *)browseId
          completion:(void (^)(NSDictionary *info, NSArray *topSongs, NSArray *allSongs, NSArray *albums, NSError *error))completion
          avatarURL:(void (^)(NSString *avatarURL))avatarBlock {
    NSDictionary *body = @{@"context": [self webRemixContext], @"browseId": browseId};
    [self postToHost:@"music.youtube.com" path:@"browse" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            if (completion) completion(nil, nil, nil, nil, error);
            return;
        }
        NSDictionary *info = [self headerInfo:json squareThumbnail:YES];
        NSArray *topSongs = [self artistTopSongs:json];
        NSArray *albums = [self artistAlbums:json];

        // Reuse this same response rather than asking again: gather every song
        // on the page, following the shelf continuation for the rest, then sort
        // by play count. The caller's completion waits for all of that so
        // "all songs" really is all of them.
        NSMutableArray *allSongs = [NSMutableArray array];
        NSMutableDictionary *counts = [NSMutableDictionary dictionary];
        NSMutableSet *seen = [NSMutableSet set];
        __unsafe_unretained LTYouTubeClient *weakSelf = self;
        [self collectArtistSongsIn:json
                            tracks:allSongs
                            counts:counts
                              seen:seen
                    remainingPages:kLTArtistSongPages
                           onDone:^{
            LTYouTubeClient *strongSelf = weakSelf;
            // Stash the count on the track so the list can show it, which is
            // also the only way to see that the ordering is really by plays.
            for (LTTrack *track in allSongs) {
                NSNumber *count = [counts objectForKey:track.videoId];
                track.playCount = count ? [count longLongValue] : -1;
            }
            [strongSelf sortArtistSongs:allSongs counts:counts];
            // Evidence that the play counts actually parsed: without this the
            // only symptom of a broken parse is a list that looks unsorted.
            NSUInteger probe = MIN((NSUInteger)5, allSongs.count);
            for (NSUInteger i = 0; i < probe; i++) {
                LTTrack *t = [allSongs objectAtIndex:i];
                LTLog(@"ARTIST top%lu '%@' plays=%@", (unsigned long)i, t.title,
                      [counts objectForKey:t.videoId] ?: @"none");
            }
            if (completion) completion(info, topSongs, allSongs, albums, nil);
        }];
    }];
    if (avatarBlock) {
        [self channelAvatarURLForBrowseId:browseId completion:avatarBlock];
    }
}

- (void)channelAvatarURLForBrowseId:(NSString *)browseId
                         completion:(void (^)(NSString *avatarURL))completion {
    if (!completion) return;
    if (![browseId isKindOfClass:[NSString class]] || ![browseId hasPrefix:@"UC"]) {
        completion(nil);
        return;
    }
    NSString *cached = [self.channelAvatarCache objectForKey:browseId];
    if (cached.length) {
        completion(cached);
        return;
    }
    NSMutableArray *pending = [self.pendingChannelAvatars objectForKey:browseId];
    if (!pending) {
        pending = [NSMutableArray array];
        [self.pendingChannelAvatars setObject:pending forKey:browseId];
    }
    [pending addObject:completion];
    if (pending.count > 1) return;

    NSDictionary *body = @{@"context": [self webContext], @"browseId": browseId};
    [self postToHost:@"www.youtube.com" path:@"browse" body:body completion:^(id json, NSError *error) {
        NSString *avatarURL = nil;
        if (!error && [json isKindOfClass:[NSDictionary class]]) {
            NSArray *thumbs = LTPath(json, @"metadata", @"channelMetadataRenderer", @"avatar", @"thumbnails", nil);
            avatarURL = [self largestThumbnailURLFromArray:thumbs];
            if (!avatarURL.length) {
                thumbs = LTPath(json, @"microformat", @"microformatDataRenderer", @"thumbnail", @"thumbnails", nil);
                avatarURL = [self largestThumbnailURLFromArray:thumbs];
            }
        }
        if (avatarURL.length) {
            [self.channelAvatarCache setObject:avatarURL forKey:browseId];
        }
        NSArray *waiters = [self.pendingChannelAvatars objectForKey:browseId] ?: [NSArray array];
        [self.pendingChannelAvatars removeObjectForKey:browseId];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void (^waiter)(NSString *) in waiters) {
                waiter(avatarURL);
            }
        });
    }];
}

- (void)resolveArtistAvatarForName:(NSString *)name
                        completion:(void (^)(NSString *avatarURL))completion {
    if (!completion) return;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) {
        completion(nil);
        return;
    }
    NSString *key = [trimmed lowercaseString];
    NSString *cached = [[LTPlaylistStore sharedStore] artistAvatarURLForName:trimmed];
    if (cached.length) {
        completion(cached);
        return;
    }
    NSMutableArray *pending = [self.pendingNameAvatars objectForKey:key];
    if (!pending) {
        pending = [NSMutableArray array];
        [self.pendingNameAvatars setObject:pending forKey:key];
    }
    [pending addObject:completion];
    if (pending.count > 1) return;

    __unsafe_unretained LTYouTubeClient *weakSelf = self;
    [self searchWithQuery:trimmed type:@"artists" completion:^(NSArray *items, NSError *error) {
        LTYouTubeClient *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *browseId = nil;
        NSString *partialId = nil;
        for (id item in items) {
            if (![item isKindOfClass:[LTBrowseItem class]]) continue;
            LTBrowseItem *bi = item;
            if (bi.kind != LTBrowseKindArtist || !bi.browseId.length) continue;
            if ([[bi.title lowercaseString] isEqualToString:key]) { browseId = bi.browseId; break; }
            if (!partialId && [bi.title rangeOfString:trimmed options:NSCaseInsensitiveSearch].location != NSNotFound) {
                partialId = bi.browseId;
            }
        }
        if (!browseId.length) browseId = partialId;

        void (^finish)(NSString *) = ^(NSString *avatarURL) {
            NSString *final = avatarURL;
            if (final.length) {
                final = [strongSelf channelAvatarURL:final size:160];
                [[LTPlaylistStore sharedStore] setArtistAvatarURL:final forName:trimmed];
            }
            NSArray *waiters = [strongSelf.pendingNameAvatars objectForKey:key] ?: [NSArray array];
            [strongSelf.pendingNameAvatars removeObjectForKey:key];
            dispatch_async(dispatch_get_main_queue(), ^{
                for (void (^waiter)(NSString *) in waiters) {
                    waiter(final);
                }
            });
        };
        if (!browseId.length) {
            finish(nil);
            return;
        }
        [strongSelf channelAvatarURLForBrowseId:browseId completion:finish];
    }];
}

- (void)resolveArtistBrowseId:(NSString *)name
                   completion:(void (^)(NSString *browseId))completion {
    if (!completion) return;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) { completion(nil); return; }
    NSString *key = [trimmed lowercaseString];
    __unsafe_unretained LTYouTubeClient *weakSelf = self;
    [self searchWithQuery:trimmed type:@"artists" completion:^(NSArray *items, NSError *error) {
        LTYouTubeClient *strongSelf = weakSelf;
        if (!strongSelf) { completion(nil); return; }
        NSString *browseId = nil;
        NSString *partialId = nil;
        for (id item in items) {
            if (![item isKindOfClass:[LTBrowseItem class]]) continue;
            LTBrowseItem *bi = item;
            if (bi.kind != LTBrowseKindArtist || !bi.browseId.length) continue;
            if ([[bi.title lowercaseString] isEqualToString:key]) { browseId = bi.browseId; break; }
            if (!partialId && [bi.title rangeOfString:trimmed options:NSCaseInsensitiveSearch].location != NSNotFound) {
                partialId = bi.browseId;
            }
        }
        if (!browseId.length) browseId = partialId;
        // Fallback: first artist result
        if (!browseId.length) {
            for (id item in items) {
                if ([item isKindOfClass:[LTBrowseItem class]]) {
                    LTBrowseItem *bi = item;
                    if (bi.kind == LTBrowseKindArtist && bi.browseId.length) { browseId = bi.browseId; break; }
                }
            }
        }
        LTLog(@"RESOLVE artist '%@' -> browseId=%@", trimmed, browseId ?: @"(none)");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(browseId); });
    }];
}

- (NSString *)channelAvatarURL:(NSString *)urlString size:(NSInteger)size {
    if (![urlString isKindOfClass:[NSString class]] || !urlString.length) return urlString;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"=s\\d+[a-z0-9_-]*(?=\\?|$)"
                                                                           options:0 error:nil];
    if ([regex rangeOfFirstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)].location != NSNotFound) {
        NSMutableString *result = [urlString mutableCopy];
        [regex replaceMatchesInString:result options:0 range:NSMakeRange(0, result.length)
                         withTemplate:[NSString stringWithFormat:@"=s%ld", (long)size]];
        return result;
    }
    return urlString;
}

#pragma mark - Trending

- (void)fetchTrendingSongsWithCompletion:(void (^)(NSArray *tracks, NSError *error))completion {
    NSDictionary *body = @{@"context": [self webRemixContext], @"browseId": @"FEmusic_charts"};
    __unsafe_unretained LTYouTubeClient *weakSelf = self;
    [self postToHost:@"music.youtube.com" path:@"browse" body:body completion:^(id json, NSError *error) {
        LTYouTubeClient *strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) completion(nil, error);
            return;
        }
        if (error || !json) {
            if (completion) completion(nil, error);
            return;
        }
        NSString *trendingId = [strongSelf trendingPlaylistIdFromCharts:json];
        if (!trendingId.length) {
            if (completion) completion(nil, [strongSelf errorWithCode:4 message:@"No trending chart found"]);
            return;
        }
        NSDictionary *playlistBody = @{@"context": [strongSelf webRemixContext], @"browseId": trendingId};
        [strongSelf postToHost:@"music.youtube.com" path:@"browse" body:playlistBody completion:^(id playlistJson, NSError *playlistError) {
            if (playlistError || !playlistJson) {
                if (completion) completion(nil, playlistError);
                return;
            }
            NSArray *tracks = [strongSelf tracksFromPlaylistShelf:playlistJson];
            if (completion) completion(tracks, nil);
        }];
    }];
}

- (NSString *)trendingPlaylistIdFromCharts:(NSDictionary *)json {
    __block NSString *trending = nil;
    __block NSString *fallback = nil;
    [self enumerateRenderersIn:json key:@"musicTwoRowItemRenderer" block:^(NSDictionary *renderer) {
        NSString *title = [self textFromRuns:[[renderer objectForKey:@"title"] objectForKey:@"runs"]];
        NSString *browseId = LTPath(renderer, @"navigationEndpoint", @"browseEndpoint", @"browseId", nil);
        if (![browseId isKindOfClass:[NSString class]] || !browseId.length) return;
        if (!fallback && [browseId hasPrefix:@"VL"]) fallback = browseId;
        if (!trending && [title rangeOfString:@"Trending"].location != NSNotFound) trending = browseId;
    }];
    if (trending.length) return trending;
    return fallback ?: @"";
}

- (NSDictionary *)headerInfo:(NSDictionary *)json squareThumbnail:(BOOL)square {
    NSString *title = nil, *subtitle = nil, *thumb = nil;

    id immersive = LTPath(json, @"header", @"musicImmersiveHeaderRenderer", nil);
    if ([immersive isKindOfClass:[NSDictionary class]]) {
        title = [self textFromRuns:[[immersive objectForKey:@"title"] objectForKey:@"runs"]];
        thumb = [self thumbnailFromHeader:immersive];
    }

    if (!title) {
        NSArray *sections = LTPath(json, @"contents", @"singleColumnBrowseResultsRenderer", @"tabs", @0,
                                   @"tabRenderer", @"content", @"sectionListRenderer", @"contents", nil);
        for (id section in sections) {
            if (![section isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *header = [section objectForKey:@"musicResponsiveHeaderRenderer"];
            if (!header) continue;
            title = [self textFromRuns:[[header objectForKey:@"title"] objectForKey:@"runs"]];
            subtitle = [self textFromRuns:[[header objectForKey:@"subtitle"] objectForKey:@"runs"]];
            thumb = [self thumbnailFromHeader:header];
            break;
        }
    }

    if (!title) {
        id detail = LTPath(json, @"contents", @"twoColumnBrowseResultsRenderer", @"tabs", @0,
                           @"tabRenderer", @"content", @"sectionListRenderer", @"contents", @0,
                           @"musicDetailHeaderRenderer", nil);
        if (![detail isKindOfClass:[NSDictionary class]]) {
            detail = LTPath(json, @"contents", @"singleColumnBrowseResultsRenderer", @"tabs", @0,
                            @"tabRenderer", @"content", @"musicDetailHeaderRenderer", nil);
        }
        if ([detail isKindOfClass:[NSDictionary class]]) {
            title = [self textFromRuns:[[detail objectForKey:@"title"] objectForKey:@"runs"]];
            subtitle = [self subtitleForDetailHeader:detail];
            thumb = [self thumbnailFromHeader:detail];
        }
    }

    if (square && thumb.length) thumb = [self squareAvatarURL:thumb size:720];

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (title.length) [info setObject:title forKey:@"title"];
    if (subtitle.length) [info setObject:subtitle forKey:@"subtitle"];
    if (thumb.length) [info setObject:thumb forKey:@"thumbnail"];
    return info;
}

- (NSString *)subtitleForDetailHeader:(NSDictionary *)detail {
    NSMutableArray *parts = [NSMutableArray array];
    NSArray *s1 = [[detail objectForKey:@"subtitle"] objectForKey:@"runs"];
    for (id run in s1) {
        if ([run isKindOfClass:[NSDictionary class]]) {
            NSString *text = [run objectForKey:@"text"];
            if (text.length) [parts addObject:text];
        }
    }
    id affects = [[detail objectForKey:@"subtitle"] objectForKey:@"content"];
    if ([affects isKindOfClass:[NSString class]] && ((NSString *)affects).length) {
        [parts addObject:affects];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (NSString *)thumbnailFromHeader:(NSDictionary *)header {
    NSArray *thumbs = LTPath(header, @"thumbnail", @"musicThumbnailRenderer", @"thumbnail", @"thumbnails", nil);
    return [self largestThumbnailURLFromArray:thumbs];
}

#pragma mark - Track parsing

- (NSArray *)tracksFromShelf:(NSDictionary *)json {
    NSMutableArray *tracks = [NSMutableArray array];
    [self enumerateRenderersIn:json key:@"musicShelfRenderer" block:^(NSDictionary *shelf) {
        id contents = [shelf objectForKey:@"contents"];
        if (![contents isKindOfClass:[NSArray class]]) return;
        for (id row in contents) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *item = [row objectForKey:@"musicResponsiveListItemRenderer"];
            if (!item) continue;
            LTTrack *track = [self trackFromItem:item];
            if (track) [tracks addObject:track];
        }
    }];
    return tracks;
}

- (NSArray *)tracksFromPlaylistShelf:(NSDictionary *)json {
    NSMutableArray *tracks = [NSMutableArray array];
    [self enumerateRenderersIn:json key:@"musicPlaylistShelfRenderer" block:^(NSDictionary *shelf) {
        id contents = [shelf objectForKey:@"contents"];
        if (![contents isKindOfClass:[NSArray class]]) return;
        for (id row in contents) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *item = [row objectForKey:@"musicResponsiveListItemRenderer"];
            if (!item) continue;
            LTTrack *track = [self trackFromItem:item];
            if (track) [tracks addObject:track];
        }
    }];
    return tracks;
}

- (LTTrack *)trackFromItem:(NSDictionary *)item {
    NSArray *flex = [item objectForKey:@"flexColumns"];
    if (![flex isKindOfClass:[NSArray class]] || flex.count == 0) return nil;
    NSArray *runs = [self runsFromFlexColumn:[flex objectAtIndex:0]];
    NSString *title = [self textFromRuns:runs];
    if (!title.length) return nil;

    NSString *videoId = LTPath(item, @"playlistItemData", @"videoId", nil);
    if (![videoId isKindOfClass:[NSString class]] || !videoId.length) {
        videoId = nil;
    }
    if (!videoId) {
        id firstRun = runs.count ? [runs objectAtIndex:0] : nil;
        NSDictionary *nav = [firstRun objectForKey:@"navigationEndpoint"];
        videoId = LTPath(nav, @"watchEndpoint", @"videoId", nil);
    }
    if (!videoId) {
        videoId = LTPath(item, @"overlay", @"content", @"musicPlayButtonRenderer",
                         @"playNavigationEndpoint", @"watchEndpoint", @"videoId", nil);
    }
    if (!videoId.length) return nil;

    LTTrack *track = [[LTTrack alloc] init];
    track.title = title;
    track.videoId = videoId;
    track.thumbnailURL = [self compatThumbnailURL:[self thumbnailFromItem:item] videoId:videoId];

    NSArray *col1 = flex.count > 1 ? [self runsFromFlexColumn:[flex objectAtIndex:1]] : nil;
    NSArray *col2 = flex.count > 2 ? [self runsFromFlexColumn:[flex objectAtIndex:2]] : nil;

    NSArray *parts1 = [self filteredRuns:col1];
    if (parts1.count) track.artist = [parts1 objectAtIndex:0];
    NSArray *parts2 = [self filteredRuns:col2];
    if (parts2.count) track.album = [parts2 objectAtIndex:0];

    NSArray *fixed = [item objectForKey:@"fixedColumns"];
    if ([fixed isKindOfClass:[NSArray class]] && fixed.count) {
        NSDictionary *fc = [[fixed objectAtIndex:0] objectForKey:@"musicResponsiveListItemFixedColumnRenderer"];
        NSArray *druns = [[fc objectForKey:@"text"] objectForKey:@"runs"];
        NSString *durText = [self textFromRuns:druns];
        track.duration = [[self class] timeFromString:durText];
    } else {
        NSArray *parts = [self filteredRuns:col1];
        if (parts.count >= 3) {
            track.duration = [[self class] timeFromString:[parts objectAtIndex:2]];
        }
    }
    return track;
}

// The token that continues a song shelf, if it has one. YouTube hangs it off
// the shelf's last row as a continuationItemRenderer.
- (NSString *)songShelfContinuationIn:(NSDictionary *)json {
    __block NSString *token = nil;
    [self enumerateRenderersIn:json key:@"musicShelfRenderer" block:^(NSDictionary *shelf) {
        if (token) return;
        id contents = [shelf objectForKey:@"contents"];
        if (![contents isKindOfClass:[NSArray class]]) return;
        for (id row in contents) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            id found = LTPath(row, @"continuationItemRenderer", @"continuationEndpoint",
                              @"continuationCommand", @"token", nil);
            if ([found isKindOfClass:[NSString class]] && [(NSString *)found length]) {
                token = found;
                break;
            }
        }
    }];
    if (!token) {
        // Also look outside the shelves: a page can hang its continuation off
        // the section list rather than the last row of a shelf.
        id continuations = [json objectForKey:@"continuations"];
        if ([continuations isKindOfClass:[NSArray class]]) {
            for (id c in continuations) {
                id found = LTPath(c, @"nextContinuationData", @"continuation", nil);
                if ([found isKindOfClass:[NSString class]] && [(NSString *)found length]) {
                    token = found;
                    break;
                }
                found = LTPath(c, @"continuationItemRenderer", @"continuationEndpoint",
                               @"continuationCommand", @"token", nil);
                if ([found isKindOfClass:[NSString class]] && [(NSString *)found length]) {
                    token = found;
                    break;
                }
            }
        }
    }
    LTLog(@"ARTISTPAGE token=%@", token ? [NSString stringWithFormat:@"found(%lu)", (unsigned long)token.length] : @"NONE");
    return token;
}

// Harvest every song in a browse payload, then follow the shelf's continuation
// for more, up to `remainingPages` extra requests.
//
// The artist's first page only carries the "Top songs" shelf, so without this
// "all songs" would mean "the dozen songs on the first page". Pages are capped
// so a prolific artist cannot turn one tap into a hundred requests on a network
// that is often blocking anyway.
//
// Always finishes on the main thread.
- (void)collectArtistSongsIn:(NSDictionary *)json
                       tracks:(NSMutableArray *)tracks
                       counts:(NSMutableDictionary *)counts
                         seen:(NSMutableSet *)seen
                 remainingPages:(NSInteger)remainingPages
                        onDone:(void (^)(void))onDone {
    [self enumerateRenderersIn:json key:@"musicShelfRenderer" block:^(NSDictionary *shelf) {
        id contents = [shelf objectForKey:@"contents"];
        if (![contents isKindOfClass:[NSArray class]]) return;
        for (id row in contents) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *item = [row objectForKey:@"musicResponsiveListItemRenderer"];
            if (!item) continue;
            LTTrack *track = [self trackFromItem:item];
            if (!track || !track.videoId.length) continue;
            if ([seen containsObject:track.videoId]) continue;
            [seen addObject:track.videoId];
            [tracks addObject:track];
            long long count = [self playCountFromItem:item];
            if (count >= 0 && ![counts objectForKey:track.videoId]) {
                [counts setObject:@(count) forKey:track.videoId];
            }
        }
    }];

    LTLog(@"ARTISTPAGE page harvested=%lu total=%lu",
          (unsigned long)seen.count, (unsigned long)tracks.count);
    NSString *token = remainingPages > 0 ? [self songShelfContinuationIn:json] : nil;
    if (!token.length) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (onDone) onDone(); });
        return;
    }

    NSDictionary *body = @{@"context": [self webRemixContext], @"continuation": token};
    [self postToHost:@"music.youtube.com" path:@"browse" body:body completion:^(id next, NSError *error) {
        if (![next isKindOfClass:[NSDictionary class]]) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (onDone) onDone(); });
            return;
        }
        [self collectArtistSongsIn:next
                            tracks:tracks
                            counts:counts
                              seen:seen
                    remainingPages:remainingPages - 1
                           onDone:onDone];
    }];
}

// Sorts a harvested song list by play count, descending.
//
// In place, because the caller is waiting on it. Songs with no count available
// sink below every counted one: an unknown count is not evidence of zero plays,
// and putting them at the top would be worse than putting them at the bottom.
// Among songs that all lack counts, the page's own order is kept.
- (void)sortArtistSongs:(NSMutableArray *)tracks counts:(NSDictionary *)counts {
    [tracks sortUsingComparator:^NSComparisonResult(LTTrack *a, LTTrack *b) {
        id ra = [counts objectForKey:a.videoId];
        id rb = [counts objectForKey:b.videoId];
        BOOL ha = ra != nil, hb = rb != nil;
        if (ha && hb) {
            long long ca = [ra longLongValue], cb = [rb longLongValue];
            if (ca > cb) return NSOrderedAscending;
            if (ca < cb) return NSOrderedDescending;
        } else if (ha != hb) {
            return ha ? NSOrderedAscending : NSOrderedDescending;
        }
        if (!ha && !hb) {
            NSUInteger ia = [tracks indexOfObject:a];
            NSUInteger ib = [tracks indexOfObject:b];
            if (ia < ib) return NSOrderedAscending;
            if (ia > ib) return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
}

// A song row's play count, parsed from its subtitle.
//
// The runs concatenate with no separator between them, so the subtitle arrives
// as one glued string: "Synthion87K plays", where "87K" is the count and
// "Synthion" the artist. The count is also frequently followed by the *next*
// row's title in the same string. Neither is a word boundary, so the number is
// found by walking backwards from "plays" over numeric characters rather than
// by splitting on whitespace, which yields "Synthion87K" and parses as nothing.
//
// Returns -1 when the row genuinely carries no count, which sorts below every
// row that has one.
- (long long)playCountFromItem:(NSDictionary *)item {
    NSArray *flex = [item objectForKey:@"flexColumns"];
    if (![flex isKindOfClass:[NSArray class]] || flex.count < 2) return -1;

    NSMutableString *subtitle = [NSMutableString string];
    // Every column after the title, so a count that has drifted into another
    // column is still found.
    for (NSUInteger i = 1; i < flex.count; i++) {
        NSArray *runs = [self runsFromFlexColumn:[flex objectAtIndex:i]];
        if (![runs isKindOfClass:[NSArray class]]) continue;
        [subtitle appendString:[self textFromRuns:runs]];
    }
    if (!subtitle.length) return -1;

    NSRange plays = [subtitle rangeOfString:@"play" options:NSCaseInsensitiveSearch];
    if (plays.location == NSNotFound) return -1;

    // Walk backwards from "plays" collecting the numeric characters directly
    // before it.
    //
    // NOT a whitespace split. The runs concatenate with no separator, so the
    // artist name arrives glued to the count - "Synthion87K plays" - and a
    // token split yields "Synthion87K", which is not a number. Scanning back
    // over digits and a K/M/B suffix stops at the first letter instead, and so
    // also survives the trailing title of the *next* row that ends up in the
    // same string.
    // Skip any whitespace sitting directly before "plays" - "87K plays" puts a
    // space there, and treating the space as the end of the number stopped the
    // walk before it ever reached the digits.
    NSUInteger end = plays.location;
    while (end > 0) {
        unichar c = [subtitle characterAtIndex:end - 1];
        if (c != ' ' && c != '\t' && c != 0x00A0) break;
        end--;
    }

    NSUInteger start = end;
    while (start > 0) {
        unichar c = [subtitle characterAtIndex:start - 1];
        BOOL numeric = (c >= '0' && c <= '9') || c == '.' || c == ',' ||
                       c == 'K' || c == 'k' || c == 'M' || c == 'm' ||
                       c == 'B' || c == 'b';
        if (!numeric) break;
        start--;
    }
    if (start == end) return -1;

    NSString *token = [subtitle substringWithRange:NSMakeRange(start, end - start)];
    // A stray suffix can leave a dangling separator, e.g. "2," - drop any
    // trailing punctuation before parsing.
    while (token.length > 1) {
        unichar last = [token characterAtIndex:token.length - 1];
        if (last != '.' && last != ',') break;
        token = [token substringToIndex:token.length - 1];
    }
    return LTParseCountToken(token);
}

- (NSArray *)artistTopSongs:(NSDictionary *)json {
    NSMutableArray *tracks = [NSMutableArray array];
    [self enumerateRenderersIn:json key:@"musicShelfRenderer" block:^(NSDictionary *shelf) {
        NSString *shelfTitle = [self textFromRuns:[[shelf objectForKey:@"title"] objectForKey:@"runs"]];
        if (![shelfTitle isEqualToString:@"Top songs"]) return;
        id contents = [shelf objectForKey:@"contents"];
        if (![contents isKindOfClass:[NSArray class]]) return;
        for (id row in contents) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *item = [row objectForKey:@"musicResponsiveListItemRenderer"];
            if (!item) continue;
            LTTrack *track = [self trackFromItem:item];
            if (track) [tracks addObject:track];
        }
    }];
    return tracks;
}

- (NSArray *)artistAlbums:(NSDictionary *)json {
    NSMutableArray *albums = [NSMutableArray array];
    __block BOOL found = NO;
    [self enumerateRenderersIn:json key:@"musicCarouselShelfRenderer" block:^(NSDictionary *car) {
        if (found) return;
        NSString *carTitle = [self textFromRuns:LTPath(car, @"header", @"musicCarouselShelfBasicHeaderRenderer", @"title", @"runs", nil)];
        if (![carTitle isEqualToString:@"Albums"]) return;
        found = YES;
        id contents = [car objectForKey:@"contents"];
        if (![contents isKindOfClass:[NSArray class]]) return;
        for (id row in contents) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *it = [row objectForKey:@"musicTwoRowItemRenderer"];
            if (!it) continue;
            NSString *browseId = LTPath(it, @"navigationEndpoint", @"browseEndpoint", @"browseId", nil);
            if (![browseId isKindOfClass:[NSString class]] || !browseId.length) continue;
            LTBrowseItem *bi = [[LTBrowseItem alloc] init];
            bi.kind = LTBrowseKindAlbum;
            bi.browseId = browseId;
            bi.title = [self textFromRuns:[[it objectForKey:@"title"] objectForKey:@"runs"]];
            bi.subtitle = [self textFromRuns:[[it objectForKey:@"subtitle"] objectForKey:@"runs"]];
            NSArray *thumbs = LTPath(it, @"thumbnailRenderer", @"musicThumbnailRenderer", @"thumbnail", @"thumbnails", nil);
            bi.thumbnailURL = [self largestThumbnailURLFromArray:thumbs];
            [albums addObject:bi];
        }
    }];
    return albums;
}

#pragma mark - Player

- (void)streamURLForVideo:(NSString *)videoId
               completion:(void (^)(NSString *streamURL, BOOL muxedStream, NSInteger audioBitrateKbps, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, NO, 0, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    __unsafe_unretained LTYouTubeClient *weakSelf = self;
    // ANDROID first: it is the only client whose stream URLs googlevideo
    // still accepts (ANDROID_VR URLs now 403 from PO-token enforcement, and
    // IOS only returns URL-less SABR formats). VR stays as a later fallback.
    [self fetchStreamURLWithContext:[self androidContext]
                         clientName:@"ANDROID"
                            videoId:videoId
                         completion:^(NSString *streamURL, BOOL muxed, NSInteger kbps, NSError *androidError) {
        if (streamURL.length) {
            if (completion) completion(streamURL, muxed, kbps, nil);
            return;
        }
        LTLog(@"STREAM falling back to ANDROID_VR client for %@", videoId);
        [weakSelf fetchStreamURLWithContext:[weakSelf androidVRContext]
                                 clientName:@"ANDROID_VR"
                                    videoId:videoId
                                 completion:^(NSString *vrURL, BOOL vrMuxed, NSInteger vrKbps, NSError *vrError) {
            if (vrURL.length) {
                if (completion) completion(vrURL, vrMuxed, vrKbps, nil);
                return;
            }
            LTLog(@"STREAM falling back to IOS client for %@", videoId);
            [weakSelf fetchStreamURLWithContext:[weakSelf iosContext]
                                     clientName:@"IOS"
                                        videoId:videoId
                                     completion:^(NSString *iosURL, BOOL iosMuxed, NSInteger iosKbps, NSError *iosError) {
                if (iosURL.length) {
                    if (completion) completion(iosURL, iosMuxed, iosKbps, nil);
                    return;
                }
                NSError *last = iosError ?: vrError ?: androidError;
                NSString *msg = [NSString stringWithFormat:@"All playback sources failed.\nLast error: %@",
                                 last.localizedDescription ?: @"unknown"];
                if (completion) completion(nil, NO, 0, [weakSelf errorWithCode:2 message:msg]);
            }];
        }];
    }];
}

- (void)fetchStreamURLWithContext:(NSDictionary *)context
                         clientName:(NSString *)clientName
                            videoId:(NSString *)videoId
                         completion:(void (^)(NSString *streamURL, BOOL muxedStream, NSInteger audioBitrateKbps, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, NO, 0, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    NSDictionary *body = @{
        @"context": context,
        @"videoId": videoId,
        @"racyCheckOk": @YES,
        @"contentCheckOk": @YES,
    };
    [self postToHost:@"www.youtube.com" path:@"player" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            if (completion) completion(nil, NO, 0, error);
            return;
        }
        NSDictionary *playability = [json objectForKey:@"playabilityStatus"];
        NSString *status = [playability objectForKey:@"status"];
        if (![status isEqualToString:@"OK"]) {
            NSString *reason = [playability objectForKey:@"reason"];
            if (!reason.length) reason = @"Playback unavailable";
            NSLog(@"LTYouTubeClient: player status=%@ reason=%@ for videoId=%@ client=%@", status, reason, videoId, clientName);
            LTLog(@"PLAYER status=%@ reason=%@ videoId=%@ client=%@", status, reason, videoId, clientName);
            if (completion) completion(nil, NO, 0, [self errorWithCode:2 message:reason]);
            return;
        }
        NSDictionary *sd = [json objectForKey:@"streamingData"];
        NSDictionary *best = nil;
        NSArray *orders = @[
            @[@141, @140, @139],
            @[@140, @141, @139],
            @[@139, @140, @141],
        ];
        NSInteger quality = 0;
        NSArray *adaptive = [sd objectForKey:@"adaptiveFormats"];
        if ([adaptive isKindOfClass:[NSArray class]]) {
            NSArray *order = [orders objectAtIndex:(NSUInteger)quality];
            for (NSNumber *itagNum in order) {
                for (NSDictionary *f in adaptive) {
                    if ([[f objectForKey:@"itag"] intValue] == [itagNum intValue] && [[f objectForKey:@"url"] length]) {
                        best = f;
                        break;
                    }
                }
                if (best) break;
            }
        }
        if (!best) {
            NSArray *progressive = [sd objectForKey:@"formats"];
            if ([progressive isKindOfClass:[NSArray class]]) {
                for (NSDictionary *f in progressive) {
                    if ([[f objectForKey:@"itag"] intValue] == 18 && [[f objectForKey:@"url"] length]) {
                        best = f;
                        break;
                    }
                }
            }
        }
        NSString *url = [best objectForKey:@"url"];
        if (best && url.length) {
            NSInteger kbps = [self audioBitrateKbpsForItag:[[best objectForKey:@"itag"] intValue]];
            NSString *mime = [best objectForKey:@"mimeType"] ?: @"";
            BOOL muxed = ([mime rangeOfString:@"video/"].location != NSNotFound);
            BOOL hasN = ([url rangeOfString:@"&n="].location != NSNotFound || [url rangeOfString:@"?n="].location != NSNotFound);
            self.lastFormatInfo = @{
                @"videoId": videoId,
                @"clientName": clientName,
                @"itag": [best objectForKey:@"itag"] ?: @(0),
                @"mimeType": mime,
                @"bitrate": [best objectForKey:@"bitrate"] ?: @(0),
                @"audioSampleRate": [best objectForKey:@"audioSampleRate"] ?: @"",
                @"muxed": @(muxed),
            };
            LTLog(@"STREAM client=%@ itag=%d kbps=%d muxed=%d videoId=%@ hasN=%d fullurl=%@", clientName, [[best objectForKey:@"itag"] intValue], (int)kbps, muxed, videoId, hasN, url);
            if (completion) completion(url, muxed, kbps, nil);
        } else {
            NSLog(@"LTYouTubeClient: no playable stream found for videoId=%@", videoId);
            if (completion) completion(nil, NO, 0, [self errorWithCode:3 message:@"No playable stream found"]);
        }
    }];
}

- (NSInteger)audioBitrateKbpsForItag:(NSInteger)itag {
    switch (itag) {
        case 141: return 256;
        case 140: return 128;
        case 139: return 48;
        case 18: return 128;
        default: return 128;
    }
}

#pragma mark - Lyrics (YouTube captions)

- (void)fetchLyricsForVideo:(NSString *)videoId
                 completion:(void (^)(NSString *lyricsText, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    [self loadCaptionTracksForVideo:videoId completion:^(NSString *captionURL, NSError *error) {
        if (error || !captionURL.length) {
            if (completion) completion(nil, error ?: [self errorWithCode:4 message:@"No lyrics available"]);
            return;
        }
        [self fetchCaptionTextAtURL:captionURL completion:completion];
    }];
}

// Ask the player endpoint for the video's caption track list and hand back the
// baseUrl of the best (non-auto-generated preferred) caption track.
- (void)loadCaptionTracksForVideo:(NSString *)videoId
                       completion:(void (^)(NSString *captionURL, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    [self loadCaptionTracksForVideo:videoId
                            context:[self webContext]
                      clientStrings:@"WEB"
                         completion:completion];
}

- (void)loadCaptionTracksForVideo:(NSString *)videoId
                          context:(NSDictionary *)context
                    clientStrings:(NSString *)clientStrings
                       completion:(void (^)(NSString *captionURL, NSError *error))completion {
    NSDictionary *body = @{
        @"context": context,
        @"videoId": videoId,
        @"racyCheckOk": @YES,
        @"contentCheckOk": @YES,
    };
    [self postToHost:@"www.youtube.com" path:@"player" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            LTLog(@"LYRICS player error for videoId=%@ client=%@ error=%@", videoId, clientStrings, error ?: @"nil-json");
            [self loadCaptionTracksWithFallback:videoId
                          firstClientString:clientStrings
                                  completion:completion];
            return;
        }
        NSDictionary *captions = [json objectForKey:@"captions"];
        NSDictionary *tracklist = [captions objectForKey:@"playerCaptionsTracklistRenderer"];
        NSArray *tracks = [tracklist objectForKey:@"captionTracks"];
        NSString *status = [[json objectForKey:@"playabilityStatus"] objectForKey:@"status"];
        LTLog(@"LYRICS player captions client=%@ tracks=%d status=%@ videoId=%@", clientStrings, (int)[tracks count], status ?: @"?", videoId);
        if (![tracks isKindOfClass:[NSArray class]] || tracks.count == 0) {
            [self loadCaptionTracksWithFallback:videoId
                          firstClientString:clientStrings
                                  completion:completion];
            return;
        }
        NSDictionary *choice = nil;
        for (NSDictionary *candidate in tracks) {
            if (![candidate isKindOfClass:[NSDictionary class]]) continue;
            NSString *kind = [candidate objectForKey:@"kind"];
            if (kind.length && ![kind isEqualToString:@"asr"]) {
                if ([[candidate objectForKey:@"baseUrl"] length]) { choice = candidate; break; }
            }
        }
        if (!choice) {
            for (NSDictionary *candidate in tracks) {
                if (![candidate isKindOfClass:[NSDictionary class]]) continue;
                if ([[candidate objectForKey:@"baseUrl"] length]) { choice = candidate; break; }
            }
        }
        NSString *baseUrl = [choice objectForKey:@"baseUrl"];
        if (!baseUrl.length) {
            [self loadCaptionTracksWithFallback:videoId
                          firstClientString:clientStrings
                                  completion:completion];
            return;
        }
        if (completion) completion(baseUrl, nil);
    }];
}

- (void)loadCaptionTracksWithFallback:(NSString *)videoId
                  firstClientString:(NSString *)firstClientString
                          completion:(void (^)(NSString *captionURL, NSError *error))completion {
    if ([firstClientString isEqualToString:@"WEB"]) {
        [self loadCaptionTracksForVideo:videoId
                                context:[self iosContext]
                          clientStrings:@"IOS"
                             completion:completion];
        return;
    }
    if ([firstClientString isEqualToString:@"IOS"]) {
        [self loadCaptionTracksForVideo:videoId
                                context:[self androidContext]
                          clientStrings:@"ANDROID"
                             completion:completion];
        return;
    }
    // The watch page is a 1.4MB HTML download that is decoded into an NSString on
    // the device. On the mbedTLS path (iOS < 7) that routinely took 60-90s and, in
    // practice, never yielded caption tracks the player endpoint had already
    // reported as absent. Fail fast there rather than stalling the lyrics pane.
    if (LTShouldUseMbedTLS()) {
        LTLog(@"LYRICS skip watch page on legacy TLS videoId=%@", videoId);
        if (completion) completion(nil, [self errorWithCode:4 message:@"No lyrics available"]);
        return;
    }
    LTLog(@"LYRICS trying watch page fallback for videoId=%@", videoId);
    [self loadCaptionTracksFromWatchPage:videoId completion:completion];
}

- (void)loadCaptionTracksFromWatchPage:(NSString *)videoId
                             completion:(void (^)(NSString *captionURL, NSError *error))completion {
    NSString *urlString = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", videoId];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];
    LTSendAsyncRequest(request, [NSOperationQueue mainQueue],^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError || !data.length) {
            LTLog(@"LYRICS watch page fetch error videoId=%@ err=%@", videoId, connectionError ?: @"no-data");
            if (completion) completion(nil, connectionError ?: [self errorWithCode:6 message:@"Watch page fetch failed"]);
            return;
        }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!html.length) {
            if (completion) completion(nil, [self errorWithCode:6 message:@"Empty watch page"]);
            return;
        }
        LTLog(@"LYRICS watch page html len=%d hasYT=%d consent=%d videoId=%@",
              (int)html.length,
              (int)[self occurrencesOf:@"ytInitialPlayerResponse" in:html],
              [html rangeOfString:@"consent.youtube.com"].location != NSNotFound,
              videoId);
        NSString *playerJSON = [self extractYTInitialPlayerResponse:html];
        LTLog(@"LYRICS watch page playerJSON len=%d hasCaptions=%d videoId=%@",
              (int)playerJSON.length,
              [playerJSON rangeOfString:@"\"captions\""].location != NSNotFound,
              videoId);
        if (!playerJSON.length) {
            LTLog(@"LYRICS no ytInitialPlayerResponse in watch page for videoId=%@", videoId);
            if (completion) completion(nil, [self errorWithCode:6 message:@"No player data in watch page"]);
            return;
        }
        NSError *jsonErr = nil;
        id obj = [S6JSON objectWithData:[playerJSON dataUsingEncoding:NSUTF8StringEncoding] error:&jsonErr];
        if (jsonErr || ![obj isKindOfClass:[NSDictionary class]]) {
            LTLog(@"LYRICS watch page JSON parse failed for videoId=%@", videoId);
            if (completion) completion(nil, jsonErr ?: [self errorWithCode:6 message:@"JSON parse failed"]);
            return;
        }
        NSDictionary *captions = [obj objectForKey:@"captions"];
        NSDictionary *tracklist = [captions objectForKey:@"playerCaptionsTracklistRenderer"];
        NSArray *tracks = [tracklist objectForKey:@"captionTracks"];
        LTLog(@"LYRICS watch page captions tracks=%d videoId=%@", (int)[tracks count], videoId);
        if (![tracks isKindOfClass:[NSArray class]] || tracks.count == 0) {
            if (completion) completion(nil, [self errorWithCode:4 message:@"No lyrics available"]);
            return;
        }
        NSDictionary *choice = nil;
        for (NSDictionary *candidate in tracks) {
            if (![candidate isKindOfClass:[NSDictionary class]]) continue;
            NSString *kind = [candidate objectForKey:@"kind"];
            if (kind.length && ![kind isEqualToString:@"asr"]) {
                if ([[candidate objectForKey:@"baseUrl"] length]) { choice = candidate; break; }
            }
        }
        if (!choice) {
            for (NSDictionary *candidate in tracks) {
                if (![candidate isKindOfClass:[NSDictionary class]]) continue;
                if ([[candidate objectForKey:@"baseUrl"] length]) { choice = candidate; break; }
            }
        }
        NSString *baseUrl = [choice objectForKey:@"baseUrl"];
        if (!baseUrl.length) {
            if (completion) completion(nil, [self errorWithCode:4 message:@"No lyrics available"]);
            return;
        }
        if (completion) completion(baseUrl, nil);
    });
}

- (NSInteger)occurrencesOf:(NSString *)needle in:(NSString *)haystack {
    if (!needle.length || !haystack.length) return 0;
    NSInteger count = 0;
    NSUInteger searchFrom = 0;
    while (YES) {
        NSRange r = [haystack rangeOfString:needle options:NSLiteralSearch range:NSMakeRange(searchFrom, haystack.length - searchFrom)];
        if (r.location == NSNotFound) break;
        count++;
        searchFrom = r.location + r.length;
        if (searchFrom >= haystack.length) break;
    }
    return count;
}

- (NSString *)extractYTInitialPlayerResponse:(NSString *)html {
    NSString *key = @"var ytInitialPlayerResponse = ";
    NSRange start = [html rangeOfString:key];
    if (start.location == NSNotFound) {
        key = @"window[\"ytInitialPlayerResponse\"] = ";
        start = [html rangeOfString:key];
    }
    if (start.location == NSNotFound) return nil;
    NSUInteger offset = start.location + start.length;
    if (offset >= html.length) return nil;
    NSUInteger braceCount = 0;
    BOOL inString = NO;
    BOOL escaped = NO;
    for (NSUInteger i = offset; i < html.length; i++) {
        unichar c = [html characterAtIndex:i];
        if (escaped) { escaped = NO; continue; }
        if (c == '\\') { escaped = YES; continue; }
        if (c == '"') { inString = !inString; continue; }
        if (inString) continue;
        if (c == '{') braceCount++;
        else if (c == '}') {
            if (braceCount == 0) break;
            braceCount--;
            if (braceCount == 0) {
                return [html substringWithRange:NSMakeRange(offset, i + 1 - offset)];
            }
        }
    }
    return nil;
}

- (void)fetchCaptionTextAtURL:(NSString *)urlString
                   completion:(void (^)(NSString *text, NSError *error))completion {
    NSString *requestURL = urlString;
    NSRange amp = [urlString rangeOfString:@"?"];
    NSString *connector = (amp.location == NSNotFound) ? @"?" : @"&";
    if ([urlString rangeOfString:@"fmt="].location == NSNotFound) {
        requestURL = [urlString stringByAppendingString:[NSString stringWithFormat:@"%@fmt=1", connector]];
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:requestURL]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];
    LTSendAsyncRequest(request, [NSOperationQueue mainQueue],^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(nil, connectionError);
            return;
        }
        NSString *raw = nil;
        if (data.length) raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!raw.length) {
            if (completion) completion(nil, [self errorWithCode:5 message:@"No caption data"]);
            return;
        }
        NSArray *lines = nil;
        if ([raw rangeOfString:@"<text"].location != NSNotFound) {
            lines = [self parseCaptionLinesFromXML:raw];
        }
        if (!lines.count && [raw rangeOfString:@"}}" options:NSLiteralSearch].location != NSNotFound) {
            lines = [self parseCaptionLinesFromJSON:raw];
        }
        if (!lines.count) {
            lines = [self parseCaptionLinesFromVTT:raw];
        }
        if (!lines.count) {
            if (completion) completion(nil, [self errorWithCode:5 message:@"No caption data"]);
            return;
        }
        if (completion) completion([lines componentsJoinedByString:@"\n"], nil);
    });
}

- (NSArray *)parseCaptionLinesFromXML:(NSString *)raw {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<text[^>]*>(.*?)</text>"
                                                                           options:NSRegularExpressionDotMatchesLineSeparators
                                                                             error:nil];
    NSArray *matches = [regex matchesInString:raw options:0 range:NSMakeRange(0, raw.length)];
    if (!matches.count) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSTextCheckingResult *match in matches) {
        NSRange range = [match rangeAtIndex:1];
        if (range.location == NSNotFound) continue;
        NSString *line = [raw substringWithRange:range];
        line = [self decodeCaptionText:line];
        line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length && [line rangeOfString:@"[Music]"].location == NSNotFound) {
            [lines addObject:line];
        }
    }
    return lines.count ? lines : nil;
}

- (NSArray *)parseCaptionLinesFromJSON:(NSString *)raw {
    NSData *data = [raw dataUsingEncoding:NSUTF8StringEncoding];
    id obj = [S6JSON objectWithData:data error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return nil;
    NSArray *events = [obj objectForKey:@"events"];
    if (![events isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *event in events) {
        if (![event isKindOfClass:[NSDictionary class]]) continue;
        NSArray *segs = [event objectForKey:@"segs"];
        if (![segs isKindOfClass:[NSArray class]]) continue;
        NSMutableString *buffer = [NSMutableString string];
        for (id seg in segs) {
            if (![seg isKindOfClass:[NSDictionary class]]) continue;
            NSString *utf8 = [seg objectForKey:@"utf8"];
            if (utf8.length) [buffer appendString:utf8];
        }
        NSString *trimmed = [buffer stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) continue;
        if ([trimmed rangeOfString:@"[Music]"].location != NSNotFound) continue;
        [lines addObject:trimmed];
    }
    return lines.count ? lines : nil;
}

- (NSArray *)parseCaptionLinesFromVTT:(NSString *)raw {
    NSArray *allLines = [raw componentsSeparatedByString:@"\n"];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in allLines) {
        NSString *candidate = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!candidate.length) continue;
        if ([candidate hasPrefix:@"WEBVTT"]) continue;
        if ([candidate rangeOfString:@"-->"].location != NSNotFound) continue;
        if ([candidate hasPrefix:@"<c."]) continue;
        NSString *stripped = [self stripVTTInlineTags:candidate];
        if (stripped.length && [stripped rangeOfString:@"[Music]"].location == NSNotFound) {
            [lines addObject:stripped];
        }
    }
    return lines.count ? lines : nil;
}

- (NSString *)stripVTTInlineTags:(NSString *)line {
    if ([line rangeOfString:@"<"].location == NSNotFound) return line;
    NSMutableString *out = [line mutableCopy];
    while (YES) {
        NSRange open = [out rangeOfString:@"<"];
        if (open.location == NSNotFound) break;
        NSRange close = [out rangeOfString:@">" options:NSLiteralSearch range:NSMakeRange(open.location, out.length - open.location)];
        if (close.location == NSNotFound) break;
        [out deleteCharactersInRange:NSMakeRange(open.location, close.location - open.location + 1)];
    }
    return out;
}

- (NSString *)decodeCaptionText:(NSString *)raw {
    if (!raw.length) return @"";
    NSMutableString *result = [raw mutableCopy];
    NSArray *pairs = @[
        @[@"&amp;", @"&"],
        @[@"&lt;", @"<"],
        @[@"&gt;", @">"],
        @[@"&quot;", @"\""],
        @[@"&#39;", @"'"],
        @[@"&nbsp;", @" "],
        @[@"♪", @""],
    ];
    for (NSArray *pair in pairs) {
        [result replaceOccurrencesOfString:[pair objectAtIndex:0]
                                withString:[pair objectAtIndex:1]
                                   options:NSLiteralSearch
                                     range:NSMakeRange(0, result.length)];
    }
    return result;
}

#pragma mark - Lyrics (YouTube Music)

// Fetches the official YouTube Music lyrics for a video, preferring the
// timestamped (synced) form returned by the mobile music client. On failure or
// when only raw text exists, yields the plain-text form; if the song has no
// lyric page at all, delegates to the caption-based path so the user still
// gets something readable.
- (void)fetchTimedLyricsForVideoId:(NSString *)videoId
                        completion:(void (^)(NSDictionary *result, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    // Step 1: watch playlist -> find the lyrics tab's browse id (MPLYt...).
    NSDictionary *body = @{
        @"context": [self webRemixContext],
        @"enablePersistentPlaylistPanel": @YES,
        @"isAudioOnly": @YES,
        @"tunerSettingValue": @"AUTOMIX_SETTING_NORMAL",
        @"videoId": videoId,
        @"playlistId": [NSString stringWithFormat:@"RDAMVM%@", videoId],
        @"watchEndpointMusicSupportedConfigs": @{
            @"watchEndpointMusicConfig": @{
                @"hasPersistentPlaylistPanel": @YES,
                @"musicVideoType": @"MUSIC_VIDEO_TYPE_ATV",
            }
        },
    };
    [self postToHost:@"music.youtube.com" path:@"next" body:body completion:^(id json, NSError *error) {
        if (error || ![json isKindOfClass:[NSDictionary class]]) {
            LTLog(@"LYRICS next failed videoId=%@ error=%@", videoId, error ?: @"bad-json");
            [self fetchLyricsForVideo:videoId completion:^(NSString *text, NSError *cerr) {
                if (completion) completion(text.length ? @{@"lyrics": text, @"source": @"", @"hasTimestamps": @NO} : nil, cerr);
            }];
            return;
        }
        NSString *browseId = [self lyricsBrowseIdFromWatchNext:json];
        if (!browseId.length) {
            LTLog(@"LYRICS no lyrics tab videoId=%@", videoId);
            [self fetchLyricsForVideo:videoId completion:^(NSString *text, NSError *cerr) {
                if (completion) completion(text.length ? @{@"lyrics": text, @"source": @"", @"hasTimestamps": @NO} : nil, cerr);
            }];
            return;
        }
        // Step 2: browse the lyrics page with the mobile music client for times.
        NSDictionary *browseBody = @{@"context": [self androidMusicContext], @"browseId": browseId};
        [self postToHost:@"music.youtube.com" path:@"browse" body:browseBody completion:^(id bjson, NSError *berr) {
            if (berr || ![bjson isKindOfClass:[NSDictionary class]]) {
                LTLog(@"LYRICS browse failed videoId=%@ browseId=%@ error=%@", videoId, browseId, berr ?: @"bad-json");
                if (completion) completion(nil, berr ?: [self errorWithCode:6 message:@"Lyrics browse failed"]);
                return;
            }
            NSDictionary *result = [self parseLyricsFromBrowse:bjson];
            if (result) {
                LTLog(@"LYRICS ok videoId=%@ hasTimestamps=%d lines=%d", videoId,
                      [[result objectForKey:@"hasTimestamps"] boolValue],
                      (int)[[result objectForKey:@"lines"] count]);
                if (completion) completion(result, nil);
                return;
            }
            // Timed + plain parsing both missed: fall back to captions.
            [self fetchLyricsForVideo:videoId completion:^(NSString *text, NSError *cerr) {
                if (completion) completion(text.length ? @{@"lyrics": text, @"source": @"", @"hasTimestamps": @NO} : nil, cerr);
            }];
        }];
    }];
}

// Walk the watch-playlist tabs for the tab whose page type is the lyrics page.
- (NSString *)lyricsBrowseIdFromWatchNext:(NSDictionary *)json {
    NSArray *tabs = LTPath(json,
        @"contents", @"singleColumnMusicWatchNextResultsRenderer",
        @"tabbedRenderer", @"watchNextTabbedResultsRenderer",
        @"tabs", nil);
    if (![tabs isKindOfClass:[NSArray class]]) return nil;
    for (id tab in tabs) {
        if (![tab isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *tabRenderer = [tab objectForKey:@"tabRenderer"];
        if (![tabRenderer isKindOfClass:[NSDictionary class]]) continue;
        if ([tabRenderer objectForKey:@"unselectable"]) continue;
        NSDictionary *endpoint = LTPath(tabRenderer, @"endpoint", @"browseEndpoint", nil);
        if (![endpoint isKindOfClass:[NSDictionary class]]) continue;
        NSString *pageType = LTPath(endpoint,
            @"browseEndpointContextSupportedConfigs",
            @"browseEndpointContextMusicConfig",
            @"pageType", nil);
        if ([pageType isEqualToString:@"MUSIC_PAGE_TYPE_TRACK_LYRICS"]) {
            NSString *bid = [endpoint objectForKey:@"browseId"];
            if ([bid isKindOfClass:[NSString class]] && bid.length) return bid;
        }
    }
    return nil;
}

// Parse the lyrics browse response: timed lines first, plain text as fallback.
- (NSDictionary *)parseLyricsFromBrowse:(NSDictionary *)json {
    NSDictionary *data = LTPath(json,
        @"contents", @"elementRenderer",
        @"newElement", @"type", @"componentType", @"model",
        @"timedLyricsModel", @"lyricsData", nil);
    if ([data isKindOfClass:[NSDictionary class]]) {
        NSArray *timed = [data objectForKey:@"timedLyricsData"];
        if ([timed isKindOfClass:[NSArray class]] && timed.count) {
            NSMutableArray *lines = [NSMutableArray array];
            for (id raw in timed) {
                if (![raw isKindOfClass:[NSDictionary class]]) continue;
                NSString *text = [raw objectForKey:@"lyricLine"];
                NSDictionary *cue = [raw objectForKey:@"cueRange"];
                NSNumber *start = [cue objectForKey:@"startTimeMilliseconds"];
                NSNumber *end = [cue objectForKey:@"endTimeMilliseconds"];
                if (![text isKindOfClass:[NSString class]]) continue;
                [lines addObject:@{
                    @"text": text,
                    @"start": start ?: @0,
                    @"end": end ?: @0,
                }];
            }
            if (lines.count) {
                NSString *source = [data objectForKey:@"sourceMessage"];
                return @{
                    @"lines": lines,
                    @"source": [source isKindOfClass:[NSString class]] ? source : @"",
                    @"hasTimestamps": @YES,
                };
            }
        }
    }
    // Plain-text shelf (non-timed browse response).
    NSString *plain = [self plainLyricsFromBrowse:json];
    if (plain.length) {
        NSString *source = LTPath(json,
            @"contents", @"sectionListRenderer", @"contents", @0,
            @"itemSectionRenderer", @"contents", @0,
            @"musicDescriptionShelfRenderer", @"runs", @0, @"text", nil);
        return @{
            @"lyrics": plain,
            @"source": [source isKindOfClass:[NSString class]] ? source : @"",
            @"hasTimestamps": @NO,
        };
    }
    return nil;
}

- (NSString *)plainLyricsFromBrowse:(NSDictionary *)json {
    id value = LTPath(json,
        @"contents", @"sectionListRenderer", @"contents", @0,
        @"itemSectionRenderer", @"contents", @0,
        @"musicDescriptionShelfRenderer", @"description", @"runs", @0, @"text", nil);
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return value;
    // Some responses put the description runs directly on the shelf.
    value = LTPath(json,
        @"contents", @"sectionListRenderer", @"contents", @0,
        @"itemSectionRenderer", @"contents", @0,
        @"musicDescriptionShelfRenderer", @"description", nil);
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return value;
    // Last-resort: the shelf itself may carry a "subheader" line.
    value = LTPath(json,
        @"contents", @"sectionListRenderer", @"contents", @0,
        @"itemSectionRenderer", @"contents", @0,
        @"musicDescriptionShelfRenderer", @"subheader", @"runs", @0, @"text", nil);
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length]) return value;
    return nil;
}

#pragma mark - Metadata

- (void)trackMetadataForVideoId:(NSString *)videoId
                     completion:(void (^)(NSString *title, NSString *artist, NSTimeInterval duration, NSString *thumbnailURL, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, nil, 0, nil, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    NSDictionary *body = @{
        @"context": [self androidVRContext],
        @"videoId": videoId,
        @"racyCheckOk": @YES,
        @"contentCheckOk": @YES,
    };
    __unsafe_unretained LTYouTubeClient *weakSelf = self;
    [self postToHost:@"www.youtube.com" path:@"player" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            if (completion) completion(nil, nil, 0, nil, error);
            return;
        }
        NSDictionary *details = [json objectForKey:@"videoDetails"];
        if (![details isKindOfClass:[NSDictionary class]]) {
            NSDictionary *playability = [json objectForKey:@"playabilityStatus"];
            NSString *reason = [playability objectForKey:@"reason"];
            if (!reason.length) reason = @"No metadata returned";
            LTLog(@"META status=%@ reason=%@ videoId=%@", [playability objectForKey:@"status"], reason, videoId);
            if (completion) completion(nil, nil, 0, nil, [weakSelf errorWithCode:2 message:reason]);
            return;
        }
        NSString *title = [details objectForKey:@"title"];
        NSString *author = [details objectForKey:@"author"];
        if ([author isKindOfClass:[NSString class]] && [author hasSuffix:@" - Topic"] && author.length > 8) {
            author = [author substringToIndex:(author.length - 8)];
        }
        NSTimeInterval duration = [[details objectForKey:@"lengthSeconds"] doubleValue];
        NSArray *thumbs = LTPath(details, @"thumbnail", @"thumbnails", nil);
        NSString *thumb = [weakSelf largestThumbnailURLFromArray:thumbs];
        if (completion) completion(title, author, duration, thumb, nil);
    }];
}

// Tries each client context in turn until one returns videoDetails.
- (void)playerDetailsForVideoId:(NSString *)videoId
                       contexts:(NSArray *)contexts
                          names:(NSArray *)names
                           index:(NSUInteger)index
                      completion:(void (^)(NSDictionary *details, NSError *error))completion {
    if (index >= contexts.count) {
        LTLog(@"GENERAL no client returned videoDetails videoId=%@", videoId);
        if (completion) completion(nil, [self errorWithCode:3 message:@"No video information returned"]);
        return;
    }
    NSString *name = [names objectAtIndex:index];
    BOOL ingest = [name isEqualToString:@"ANDROID"] || [name isEqualToString:@"ANDROID_VR"];
    NSDictionary *body = @{
        @"context": [contexts objectAtIndex:index],
        @"videoId": videoId,
        @"racyCheckOk": @YES,
        @"contentCheckOk": @YES,
    };
    __unsafe_unretained LTYouTubeClient *weakSelf = self;
    [self postToHost:@"www.youtube.com" path:@"player" body:body ingestingVisitorData:ingest completion:^(id json, NSError *error) {
        LTYouTubeClient *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary *details = LTPath(json, @"videoDetails", nil);
        if ([details isKindOfClass:[NSDictionary class]]) {
            LTLog(@"GENERAL videoDetails via %@ videoId=%@", name, videoId);
            if (completion) completion(details, nil);
            return;
        }
        NSString *status = LTPath(json, @"playabilityStatus", @"status", nil);
        NSString *reason = LTPath(json, @"playabilityStatus", @"reason", nil) ?: @"";
        LTLog(@"GENERAL client %@ unusable videoId=%@ status=%@ reason=%@",
              name, videoId, status ?: @"?", reason);
        // Bot walls do not clear between tracks. Cache them briefly so the client
        // is skipped rather than retried on the next load.
        if ([status isEqualToString:@"LOGIN_REQUIRED"] ||
            [reason rangeOfString:@"not a bot" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [strongSelf markPlayerClientBlocked:name];
        }
        [strongSelf playerDetailsForVideoId:videoId contexts:contexts names:names index:index + 1 completion:completion];
    }];
}

#pragma mark - Video general information

// Collects the descriptive facts about a video for the player's General page:
// the original YouTube title, who uploaded it, view count, like count and the
// uploader's channel.
//
// This needs two endpoints. -player carries videoDetails, which is where the view
// count lives -- note that the existing -trackMetadataForVideoId: fetches this
// same payload and discards viewCount. -next carries the like button and the
// video owner, and neither appears in -player at all.
//
// The Android VR client is used for both because it already returns both halves;
// the comment continuation endpoint only exists under WEB/MWEB, but that is not
// needed here.
//
// Yields a dictionary that may contain any of: title, uploader, channelId,
// viewCount, likeCount, avatarURL, durationSeconds. Missing fields are simply
// absent rather than nil-filled, so the caller can show only what it got.
- (void)fetchVideoGeneralInfoForVideoId:(NSString *)videoId
                              completion:(void (^)(NSDictionary *info, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    // This page is opened repeatedly for the same track. Answer from the bounded
    // cache first so a reopen costs nothing and never waits on the network.
    NSDictionary *cachedInfo = [self.generalInfoCache objectForKey:videoId];
    if (cachedInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(cachedInfo, nil);
        });
        return;
    }
    __unsafe_unretained LTYouTubeClient *weakSelf = self;

    // The player endpoint is the one call that gets bot-blocked, and it is blocked
    // per client: the VR context started returning playabilityStatus
    // LOGIN_REQUIRED / "Sign in to confirm you're not a bot" while search, playback
    // and lyrics carried on working. So -player is tried across a chain of clients
    // and the first one that yields videoDetails wins, the same shape as the
    // ANDROID -> ANDROID_VR -> IOS chain used for stream URLs.
    //
    // visitorData is harvested only from the ANDROID family. IOS and WEB issue
    // their own tokens, and folding those into the shared cache is what previously
    // broke unrelated VR requests.
    // ANDROID_VR goes last: on the 3GS it is the one that reliably answers
    // LOGIN_REQUIRED, and trying it first put a doomed handshake at the head of
    // every load. The others have been returning videoDetails consistently.
    NSMutableArray *contexts = [NSMutableArray arrayWithCapacity:4];
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:4];
    NSArray *candidates = @[@"ANDROID", @"IOS", @"WEB", @"ANDROID_VR"];
    for (NSString *name in candidates) {
        if ([self isPlayerClientBlocked:name]) continue;
        [names addObject:name];
        if ([name isEqualToString:@"ANDROID_VR"]) [contexts addObject:[self androidVRContext]];
        else if ([name isEqualToString:@"ANDROID"]) [contexts addObject:[self androidContext]];
        else if ([name isEqualToString:@"IOS"]) [contexts addObject:[self iosContext]];
        else [contexts addObject:[self webContext]];
    }
    if (!names.count) {
        if (completion) completion(nil, [self errorWithCode:3 message:@"No video information returned"]);
        return;
    }
    [self playerDetailsForVideoId:videoId
                        contexts:contexts
                           names:names
                            index:0
                       completion:^(NSDictionary *details, NSError *error) {
        LTYouTubeClient *strongSelf = weakSelf;
        if (!strongSelf) return;

        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        if ([details isKindOfClass:[NSDictionary class]]) {
            NSString *title = [details objectForKey:@"title"];
            if ([title isKindOfClass:[NSString class]] && title.length) [info setObject:title forKey:@"title"];

            NSString *author = [details objectForKey:@"author"];
            if ([author isKindOfClass:[NSString class]] && author.length) [info setObject:author forKey:@"uploader"];

            NSString *channelId = [details objectForKey:@"channelId"];
            if ([channelId isKindOfClass:[NSString class]] && channelId.length) [info setObject:channelId forKey:@"channelId"];

            NSString *views = LTFormatCount([details objectForKey:@"viewCount"]);
            if (views) [info setObject:views forKey:@"viewCount"];

            NSString *seconds = [details objectForKey:@"lengthSeconds"];
            if (seconds.length) [info setObject:seconds forKey:@"durationSeconds"];
        }

        NSDictionary *nextBody = @{
            @"context": [strongSelf androidVRContext],
            @"videoId": videoId,
        };
        [strongSelf postToHost:@"www.youtube.com" path:@"next" body:nextBody completion:^(id nextJSON, NSError *nextError) {
            LTYouTubeClient *innerSelf = weakSelf;
            if (!innerSelf) return;

            if (nextJSON) {
                NSDictionary *meta = LTFindFirstValue(nextJSON, @"videoMetadataRenderer", 14);
                NSString *likes = LTFormatCount(LTPath(meta, @"likeButton", @"likeButtonRenderer", @"likeCount", nil));
                if (likes) [info setObject:likes forKey:@"likeCount"];

                NSDictionary *owner = LTFindFirstValue(nextJSON, @"videoOwnerRenderer", 14);
                if ([owner isKindOfClass:[NSDictionary class]]) {
                    NSString *ownerTitle = LTRunText([owner objectForKey:@"title"]);
                    if (ownerTitle.length && ![info objectForKey:@"uploader"]) [info setObject:ownerTitle forKey:@"uploader"];
                    NSString *browseId = LTPath(owner, @"navigationEndpoint", @"browseEndpoint", @"browseId", nil);
                    if (browseId.length && ![info objectForKey:@"channelId"]) [info setObject:browseId forKey:@"channelId"];
                    NSArray *thumbs = LTPath(owner, @"thumbnail", @"thumbnails", nil);
                    NSString *avatar = [innerSelf largestThumbnailURLFromArray:thumbs];
                    if (avatar) [info setObject:avatar forKey:@"avatarURL"];
                }
            }

            if (!info.count && error) {
                if (completion) completion(nil, error);
                return;
            }
            // Always finish on the main thread; postToHost: already does, but the
            // nested call makes that worth being explicit about.
            NSDictionary *finalInfo = info.count ? [NSDictionary dictionaryWithDictionary:info] : nil;
            if (finalInfo) [innerSelf.generalInfoCache setObject:finalInfo forKey:videoId];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(finalInfo, finalInfo ? nil : (error ?: [strongSelf errorWithCode:3 message:@"No video information returned"]));
            });
        }];
    }];
}

#pragma mark - Images

static BOOL LTBorderRowUniform(const UInt8 *px, size_t W, size_t y,
                               size_t x0, size_t x1, const UInt8 *ref) {
    const UInt8 *row = px + y * W * 4;
    for (size_t x = x0; x < x1; x++) {
        const UInt8 *p = row + x * 4;
        if (abs(p[0] - ref[0]) > 18 || abs(p[1] - ref[1]) > 18 || abs(p[2] - ref[2]) > 18) return NO;
    }
    return YES;
}

static BOOL LTBorderColUniform(const UInt8 *px, size_t W, size_t x,
                               size_t y0, size_t y1, const UInt8 *ref) {
    for (size_t y = y0; y < y1; y++) {
        const UInt8 *p = px + (y * W + x) * 4;
        if (abs(p[0] - ref[0]) > 18 || abs(p[1] - ref[1]) > 18 || abs(p[2] - ref[2]) > 18) return NO;
    }
    return YES;
}

// Cost in bytes for the artwork cache, so its totalCostLimit is actually
// enforced: an NSCache ignores the limit entirely unless every entry is stored
// with a cost. Assumes 4 bytes/pixel, the budget LTImageCacheBudget is set to
// multiply out against.
static NSUInteger LTImageCacheCost(UIImage *image) {
    CGImageRef cg = image.CGImage;
    if (!cg) return 1;
    return CGImageGetWidth(cg) * CGImageGetHeight(cg) * 4;
}

// Removes uniform border padding YouTube pads onto some cover art so the
// artwork always fills its square edge-to-edge. Topic-video thumbs are a
// square cover centered on letterbox AND pillarbox bars of different colors,
// so trimming re-references the corner color after each pass until stable.
// For i.ytimg.com thumbs (allowCenterCrop) the cover is always centered, so
// a final centered crop of the long edge removes any bars the border scan
// could not classify.
static UIImage *LTTrimmedArtworkImage(UIImage *image, BOOL allowCenterCrop) {
    CGImageRef cg = image.CGImage;
    if (!cg) return image;
    size_t W = CGImageGetWidth(cg);
    size_t H = CGImageGetHeight(cg);
    if (W < 64 || H < 64) return image;

    NSUInteger bpr = W * 4;
    UInt8 *px = (UInt8 *)malloc(bpr * H);
    if (!px) return image;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, W, H, 8, bpr, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) {
        free(px);
        return image;
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, W, H), cg);
    CGContextRelease(ctx);

    size_t top = 0, bottom = H, left = 0, right = W;
    for (int pass = 0; pass < 4; pass++) {
        const UInt8 *ref = px + (top * W + left) * 4;
        size_t ot = top, ob = bottom, ol = left, orr = right;
        while (top < bottom - 1 && LTBorderRowUniform(px, W, top, left, right, ref)) top++;
        while (bottom > top + 1 && LTBorderRowUniform(px, W, bottom - 1, left, right, ref)) bottom--;
        while (left < right - 1 && LTBorderColUniform(px, W, left, top, bottom, ref)) left++;
        while (right > left + 1 && LTBorderColUniform(px, W, right - 1, top, bottom, ref)) right--;
        if (top == ot && bottom == ob && left == ol && right == orr) break;
        // Keep each stage only if it leaves a sane crop; later stages peel
        // letterbox bars off a different color than earlier ones, but must
        // never chew into the artwork itself.
        size_t cw = right - left, ch = bottom - top;
        if (cw < 32 || ch < 32 || cw * 2 < W || ch * 2 < H) {
            top = ot; bottom = ob; left = ol; right = orr;
            break;
        }
    }
    free(px);

    size_t cw = right - left;
    size_t ch = bottom - top;
    // Center-crop to a square for video thumbnails.
    //
    // This has to run even when the border scan above trimmed nothing. A plain
    // 16:9 video still has no uniform bars for that scan to find, so it used to
    // hit the "nothing was trimmed" early return and stay landscape, leaving a
    // letterboxed strip down each side of the artwork in a square frame.
    if (allowCenterCrop && cw != ch) {
        if (cw > ch) {
            left += (cw - ch) / 2;
            cw = ch;
        } else {
            top += (ch - cw) / 2;
            ch = cw;
        }
    } else if (cw >= W && ch >= H) {
        return image;
    }

    CGImageRef sub = CGImageCreateWithImageInRect(cg, CGRectMake((CGFloat)left, (CGFloat)top, (CGFloat)cw, (CGFloat)ch));
    if (!sub) return image;
    UIImage *trimmed = [UIImage imageWithCGImage:sub scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(sub);
    return trimmed ?: image;
}

// Scales an image down so its long edge is at most maxPixel.
//
// WHY: the artwork cache held full-resolution YouTube covers -- 1200x1200
// JPEGs of 700-800KB each, 31MB across 191 files on a test device. Decoding one
// costs a 5.7MB RGBA allocation before anything else can happen to it. Moving
// that to a background queue did not make it free: a 3GS has effectively one
// core, so several decodes running concurrently starve the main thread and the
// incoming tab stalls anyway.
//
// The result is what actually gets cached and what gets written back to disk, so
// the cache shrinks toward ~1.6MB per entry as files are revisited, and the
// large files already on disk are rewritten smaller for free.
//
// 640 covers the largest artwork the app ever draws (a full-width cover on a
// 320pt-wide @2x screen), so this is not a visible quality trade.
static UIImage *LTDownscaledImage(UIImage *image, CGFloat maxPixel) {
    CGImageRef cg = image.CGImage;
    if (!cg) return image;
    size_t W = CGImageGetWidth(cg);
    size_t H = CGImageGetHeight(cg);
    CGFloat longest = (CGFloat)MAX(W, H);
    if (longest <= maxPixel) return image;

    CGFloat scale = maxPixel / longest;
    size_t w = (size_t)MAX(1.0f, roundf((CGFloat)W * scale));
    size_t h = (size_t)MAX(1.0f, roundf((CGFloat)H * scale));
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    if (!cs) return image;
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(cs);
    if (!ctx) return image;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), cg);
    CGImageRef scaled = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!scaled) return image;
    UIImage *out = [UIImage imageWithCGImage:scaled];
    CGImageRelease(scaled);
    return out;
}

// Longest edge any decoded artwork is allowed to be.
static const CGFloat kLTArtworkMaxPixel = 640.0f;

// Queue for decode/downsample/trim work.
//
// Kept simple and iOS 4.1-compatible: iOS 4.1 lacks
// DISPATCH_QUEUE_PRIORITY_BACKGROUND and retargeting private queues can be
// problematic, so avoid background-priority retargeting here.
static dispatch_queue_t LTArtworkQueue(void) {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.legacymusic.artwork", NULL);
    });
    return queue;
}

// Caps how many artwork jobs run at once. Two was chosen by eye: enough that a
// list of thumbnails fills in without feeling serialised, few enough that the
// main thread is not competing with a dozen decodes.
static dispatch_semaphore_t LTArtworkSlots(void) {
    static dispatch_semaphore_t sem = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sem = dispatch_semaphore_create(2); });
    return sem;
}

// Disk paths whose artwork has already had the uniform-border trim applied.
//
// The trimmed image is what gets written back to disk, so re-reading it and
// trimming again is pure waste: a malloc, a full-image RGBA resample and up to
// four passes of per-pixel comparison, per image, on every load. Artwork paths
// are content-addressed (an MD5 of the URL) so the contents of a given path never
// change, which makes this safe to remember for the life of the process.
static BOOL LTPathIsTrimmed(NSString *path) {
    static NSMutableSet *trimmed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ trimmed = [[NSMutableSet alloc] init]; });
    @synchronized (trimmed) { return [trimmed containsObject:path]; }
}

static void LTMarkPathTrimmed(NSString *path) {
    static NSMutableSet *trimmed = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ trimmed = [[NSMutableSet alloc] init]; });
    @synchronized (trimmed) {
        // Bounded: the cache can outlive a lot of browsing, and this is only ever
        // an optimisation. When it overflows, start over rather than grow.
        if (trimmed.count > 3000) [trimmed removeAllObjects];
        [trimmed addObject:path];
    }
}

// On-disk artwork is only rewritten when the cached file is a full-resolution
// one. Re-encoding on every single hit cost a JPEG encode plus an atomic file
// write per image per read, which is most of why a "disk hit" measured 400ms.
static const unsigned long long kLTArtworkRewriteThreshold = 150 * 1024;

// Queue for JSON response parsing.
//
// Serial at low/background priority: on a single-core device a few hundred KB of
// JSON parsed on the main thread is a visible freeze. iOS 4.1 lacks
// DISPATCH_QUEUE_PRIORITY_BACKGROUND and is sensitive to retargeting private
// queues, so keep this simple and compatible.
static dispatch_queue_t LTJSONQueue(void) {
    static dispatch_queue_t queue = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.legacymusic.json", NULL);
    });
    return queue;
}

// Loads artwork, hitting the in-memory cache, then the on-disk JPEG cache, then
// the network.
//
// THREADING: the disk read, the JPEG decode and the border-trim scan all happen
// on a background queue and the completion is always delivered on the main
// queue. They used to run synchronously on the calling thread, which is almost
// always the main thread. A memory-cache hit still completes synchronously, so
// the common already-warm case (scrolling back through a list) keeps its
// zero-latency behaviour and callers that care still see the image set by the
// time this returns.
// Token recording what a cell was last asked to display. An associated object
// rather than a property on UITableViewCell so it works for the plain and
// custom cells alike, and cannot collide with accessibilityIdentifier (which
// these lists already use to hold artist names).
static const void *kLTArtworkCellTokenKey = &kLTArtworkCellTokenKey;

- (void)loadArtworkURL:(NSString *)urlString intoCell:(UITableViewCell *)cell {
    if (!cell) return;
    // Empty is a legitimate token: it means "this row has no artwork", so a
    // late reply for a real URL must not land on it.
    NSString *token = urlString ?: @"";
    objc_setAssociatedObject(cell, kLTArtworkCellTokenKey, token, OBJC_ASSOCIATION_COPY_NONATOMIC);
    cell.imageView.image = nil;
    if (!urlString.length) return;

    NSString *artURL = [self highResThumbnailURL:urlString];
    if (!artURL.length) return;

    // Hold the cell strongly until the reply lands. With an unsafe-unretained
    // capture a scrolled-away cell can be gone by then, and the callback then
    // messages freed memory (seen on the 3GS as an unrecognised selector).
    [self loadImageWithURL:artURL completion:^(UIImage *image) {
        UITableViewCell *strongCell = cell;
        if (!strongCell) return;
        NSString *current = objc_getAssociatedObject(strongCell, kLTArtworkCellTokenKey);
        if (![current isEqualToString:token]) return; // recycled onto another row
        if (image) strongCell.imageView.image = image;
    }];
}

- (void)loadImageWithURL:(NSString *)urlString
              completion:(void (^)(UIImage *image))completion {
    if (!urlString.length) {
        if (completion) completion(nil);
        return;
    }

    // A signed i.ytimg video thumb is not a usable artwork source on its own:
    // once its token lapses the body it returns will not decode, and the caller
    // gets nil and draws an empty cell. Almost every in-app surface loads
    // artwork straight from track.thumbnailURL, so this is the common case, not
    // an edge one. Walk the size ladder instead, starting from the equivalent
    // permanent named size rather than the dead signature.
    if ([self isSignedYouTubeThumbURL:urlString]) {
        NSString *bare = [urlString substringToIndex:[urlString rangeOfString:@"?"].location];
        NSArray *candidates = [self artworkCandidateURLsForBaseURL:bare];
        if (candidates.count) {
            LTLog(@"IMG load signed thumb -> ladder of %d", (int)candidates.count);
            [self loadArtworkFromCandidates:candidates index:0 completion:completion];
            return;
        }
    }

    LTLog(@"IMG load url=%@", urlString);
    UIImage *cached = [self.imageCache objectForKey:urlString];
    if (cached) {
        if (completion) completion(cached);
        return;
    }
    NSString *diskPath = [self diskCachePathForURL:urlString];
    NSString *cacheKey = urlString;
    BOOL centerCrop = [urlString rangeOfString:@"i.ytimg.com"].location != NSNotFound;
    dispatch_async(LTArtworkQueue(), ^{
        dispatch_semaphore_wait(LTArtworkSlots(), DISPATCH_TIME_FOREVER);
        @autoreleasepool {
            // TEMP instrumentation: see LTTabBarController -snapshotContentOfView.
            CFAbsoluteTime tArt = CFAbsoluteTimeGetCurrent();
            UIImage *diskImage = [UIImage imageWithContentsOfFile:diskPath];
            if (diskImage) {
                // Shrink only when the file on disk is still full-resolution, so this
                // is a one-time cost per image rather than work on every read.
                NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:diskPath error:nil];
                BOOL oversized = [(NSNumber *)[attrs objectForKey:NSFileSize] unsignedLongLongValue] > kLTArtworkRewriteThreshold;
                if (oversized) diskImage = LTDownscaledImage(diskImage, kLTArtworkMaxPixel);
                if (!LTPathIsTrimmed(diskPath)) {
                    diskImage = LTTrimmedArtworkImage(diskImage, centerCrop);
                    LTMarkPathTrimmed(diskPath);
                }
                LTLog(@"TABPROF art disk %.0fx%.0f took=%.0fms%s", (double)diskImage.size.width,
                      (double)diskImage.size.height, (CFAbsoluteTimeGetCurrent() - tArt) * 1000.0,
                      oversized ? " (rewritten)" : "");
                LTLog(@"IMG disk-hit url=%@", cacheKey);
                [[self imageCache] setObject:diskImage forKey:cacheKey cost:LTImageCacheCost(diskImage)];
                if (oversized) {
                    // Self-heal: write the downscaled version back so the next read
                    // decodes a small file instead of a full-size one.
                    NSData *smaller = UIImageJPEGRepresentation(diskImage, 0.85);
                    if (smaller.length) [smaller writeToFile:diskPath atomically:YES];
                }
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(diskImage); });
            } else {
                NSString *fallback = nil;
                if ([cacheKey hasSuffix:@"maxresdefault.jpg"]) {
                    fallback = [cacheKey stringByReplacingOccurrencesOfString:@"maxresdefault.jpg"
                                                                    withString:@"sddefault.jpg"];
                }
                // fetchImageAtURL: is NSURLConnection-based and already async.
                [self fetchImageAtURL:cacheKey fallbackURL:fallback diskPath:diskPath cacheKey:cacheKey completion:completion];
            }
        }
        dispatch_semaphore_signal(LTArtworkSlots());
    });
}

- (void)fetchImageAtURL:(NSString *)urlString
            fallbackURL:(NSString *)fallbackURL
               diskPath:(NSString *)diskPath
              cacheKey:(NSString *)cacheKey
             completion:(void (^)(UIImage *image))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                            cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                                        timeoutInterval:10.0];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];

    void (^handleResponse)(NSData *, NSError *) = ^(NSData *data, NSError *connectionError) {
        // Everything from here down is heavy: a full JPEG decode of a 1200x1200
        // cover, a resample, a per-pixel border scan, a JPEG encode and a flash
        // write. That is well over a second of CPU on a 3GS.
        //
        // THREADING: this used to run wherever the network callback landed, which
        // on iOS 6 meant the main thread -- NSURLConnection takes a queue and the
        // app passed the main one. That showed up as the UI freezing solid
        // whenever a screen's artwork arrived (a measured 913ms main-thread
        // stall), and because the artwork queue is serial it also blocked every
        // other image load queued behind it.
        //
        // The work now always goes to LTArtworkQueue() no matter which path
        // delivered the bytes, and only the caller's completion hops back to main.
        // Everything in here is safe off-main: the cache is an NSCache, and the
        // only UIKit-facing object, completion, is deferred.
        dispatch_async(LTArtworkQueue(), ^{
            @autoreleasepool {
                UIImage *image = nil;
                if (!connectionError && data.length) image = [UIImage imageWithData:data];
                BOOL usable = image && ([cacheKey rangeOfString:@"maxresdefault"].location == NSNotFound || image.size.width >= 200);
                LTLog(@"ART fetch url=%@ len=%lu decoded=%dx%d usable=%d err=%@",
                      urlString,
                      (unsigned long)data.length,
                      image ? (int)image.size.width : 0,
                      image ? (int)image.size.height : 0,
                      usable ? 1 : 0,
                      connectionError ? connectionError.localizedDescription : @"none");
                if (!usable) {
                    if (fallbackURL.length) {
                        [self fetchImageAtURL:fallbackURL fallbackURL:nil diskPath:diskPath cacheKey:cacheKey completion:completion];
                        return;
                    }
                    dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil); });
                    return;
                }
                image = LTDownscaledImage(image, kLTArtworkMaxPixel);
                image = LTTrimmedArtworkImage(image, [cacheKey rangeOfString:@"i.ytimg.com"].location != NSNotFound);
                [[self imageCache] setObject:image forKey:cacheKey cost:LTImageCacheCost(image)];
                NSData *encoded = UIImageJPEGRepresentation(image, 0.85);
                if (encoded) [encoded writeToFile:diskPath atomically:YES];
                // Always call completion on the main thread so UI updates work
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(image);
                });
            }
        });
    };

    // Use NSURLSession on iOS 7+ (NSURLConnection is deprecated and silently fails on iOS 10+)
    Class sessionClass = NSClassFromString(@"NSURLSession");
    if (sessionClass) {
        id session = [sessionClass performSelector:@selector(sharedSession)];
        id task = nil;
        if (session) {
            SEL sel = @selector(dataTaskWithRequest:completionHandler:);
            if ([session respondsToSelector:sel]) {
                // performSelector supports up to 2 object args; use NSInvocation for 2+.
                NSMethodSignature *sig = [session methodSignatureForSelector:sel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:sel];
                [inv setTarget:session];
                [inv setArgument:&request atIndex:2];
                void (^handler)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
                    handleResponse(data, error);
                };
                [inv setArgument:&handler atIndex:3];
                [inv invoke];
                [inv getReturnValue:&task];
            }
        }
        if (task) { [task performSelector:@selector(resume)]; }
        else {
            LTSendAsyncRequest(request, [NSOperationQueue mainQueue],^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                handleResponse(data, connectionError);
            });
        }
    } else {
        LTSendAsyncRequest(request, [NSOperationQueue mainQueue],^(NSURLResponse *response, NSData *data, NSError *connectionError) {
            handleResponse(data, connectionError);
        });
    }
}

// Walk a list of candidate artwork URLs, best first, and deliver the first one
// that is genuinely large enough.
//
// This exists because a missing YouTube "maxresdefault" is not an error: it
// answers HTTP 404 with a valid 120x90 JPEG. Decoding succeeds, so naive code
// happily displays a blurry thumbnail. Anything narrower than
// kMinUsableArtworkWidth is treated as a placeholder and the next candidate is
// tried.
- (void)loadArtworkFromCandidates:(NSArray *)urls
                              index:(NSUInteger)index
                        completion:(void (^)(UIImage *image))completion {
    if (index >= [urls count]) {
        if (completion) completion(nil);
        return;
    }
    NSString *url = [urls objectAtIndex:index];
    __unsafe_unretained LTYouTubeClient *weakSelf = self;
    [self loadImageWithURL:url completion:^(UIImage *image) {
        LTYouTubeClient *strongSelf = weakSelf;
        if (!image) {
            [strongSelf loadArtworkFromCandidates:urls index:index + 1 completion:completion];
            return;
        }
        if (image.size.width < (CGFloat)kMinUsableArtworkWidth && index + 1 < [urls count]) {
            // Placeholder (or unusually small): try a better one. Do not cache
            // this image under the higher-quality URL, or we would keep
            // rediscovering the placeholder on every launch.
            LTLog(@"ART placeholder %dx%d from %@, trying next", (int)image.size.width, (int)image.size.height, url);
            [strongSelf loadArtworkFromCandidates:urls index:index + 1 completion:completion];
            return;
        }
        if (completion) completion(image);
    }];
}

- (UIImage *)cachedArtworkForURL:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || !urlString.length) return nil;
    NSString *path = [self diskCachePathForURL:urlString];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [UIImage imageWithContentsOfFile:path];
}

- (NSString *)diskCachePathForURL:(NSString *)urlString {
    NSString *dir = [[LTPlaylistStore sharedStore] artDirectory];
    uint8_t digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5([urlString UTF8String], (CC_LONG)[urlString lengthOfBytesUsingEncoding:NSUTF8StringEncoding], digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:(CC_MD5_DIGEST_LENGTH * 2)];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", digest[i]];
    }
    return [dir stringByAppendingPathComponent:[hex stringByAppendingString:@".jpg"]];
}

#pragma mark - Helpers

- (void)enumerateRenderersIn:(id)obj key:(NSString *)key block:(void (^)(NSDictionary *renderer))block {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = obj;
        id value = [dict objectForKey:key];
        if ([value isKindOfClass:[NSDictionary class]]) block(value);
        for (id k in dict) {
            [self enumerateRenderersIn:[dict objectForKey:k] key:key block:block];
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id v in obj) {
            [self enumerateRenderersIn:v key:key block:block];
        }
    }
}

- (NSArray *)runsFromFlexColumn:(NSDictionary *)flex {
    if (![flex isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *col = [flex objectForKey:@"musicResponsiveListItemFlexColumnRenderer"];
    id runs = [[col objectForKey:@"text"] objectForKey:@"runs"];
    if ([runs isKindOfClass:[NSArray class]]) return runs;
    id simple = [[col objectForKey:@"text"] objectForKey:@"simpleText"];
    if ([simple isKindOfClass:[NSString class]] && [(NSString *)simple length]) {
        return @[@{@"text": simple}];
    }
    return nil;
}

- (NSString *)textFromRuns:(NSArray *)runs {
    if (![runs isKindOfClass:[NSArray class]]) return @"";
    NSMutableString *result = [NSMutableString string];
    for (id run in runs) {
        if (![run isKindOfClass:[NSDictionary class]]) continue;
        id text = [run objectForKey:@"text"];
        if ([text isKindOfClass:[NSString class]]) [result appendString:text];
    }
    return result;
}

- (NSArray *)filteredRuns:(NSArray *)runs {
    if (![runs isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *parts = [NSMutableArray array];
    for (id run in runs) {
        if (![run isKindOfClass:[NSDictionary class]]) continue;
        id text = [run objectForKey:@"text"];
        if (![text isKindOfClass:[NSString class]]) continue;
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!trimmed.length) continue;
        if ([trimmed rangeOfString:@"•"].location != NSNotFound) continue;
        [parts addObject:trimmed];
    }
    return parts;
}

- (NSString *)thumbnailFromItem:(NSDictionary *)item {
    NSArray *thumbs = LTPath(item, @"thumbnail", @"musicThumbnailRenderer", @"thumbnail", @"thumbnails", nil);
    return [self largestThumbnailURLFromArray:thumbs];
}

- (NSString *)squareAvatarURL:(NSString *)urlString size:(NSInteger)size {
    if (![urlString isKindOfClass:[NSString class]] || !urlString.length) return urlString;
    // yt3/lh3 service resolves size params against the ORIGINAL uploaded
    // square avatar, so rewriting the (possibly landscape-banner) spec to a
    // square request yields the artist's actual profile icon.
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"=w\\d+-h\\d+[a-z0-9_\\-]*$"
                                                                           options:0 error:nil];
    NSString *squareSpec = [NSString stringWithFormat:@"=w%ld-h%ld-p-l90-rj", (long)size, (long)size];
    if ([regex rangeOfFirstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)].location != NSNotFound) {
        NSMutableString *result = [urlString mutableCopy];
        [regex replaceMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:squareSpec];
        return result;
    }
    if ([urlString rangeOfString:@"googleusercontent.com"].location != NSNotFound) {
        return [urlString stringByAppendingString:squareSpec];
    }
    return urlString;
}

- (NSString *)compatThumbnailURL:(NSString *)urlString videoId:(NSString *)videoId {
    if (!urlString.length || !videoId.length) return urlString;
    if ([[[UIDevice currentDevice] systemVersion] intValue] >= 7) return urlString;
    if ([urlString rangeOfString:@"i.ytimg.com"].location != NSNotFound) return urlString;
    // Pre-7.0 iOS TLS cannot negotiate lh3.googleusercontent.com / ggpht TLS 1.2,
    // so fall back to the i.ytimg mirror, which is what offline tracks already use.
    return [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/sddefault.jpg", videoId];
}

- (NSString *)largestThumbnailURLFromArray:(NSArray *)thumbs {
    if (![thumbs isKindOfClass:[NSArray class]] || thumbs.count == 0) return nil;
    NSDictionary *best = nil;
    NSInteger bestWidth = -1;
    for (id t in thumbs) {
        if (![t isKindOfClass:[NSDictionary class]]) continue;
        NSString *url = [t objectForKey:@"url"];
        if (![url isKindOfClass:[NSString class]] || !url.length) continue;
        NSInteger width = [[t objectForKey:@"width"] integerValue];
        if (!best || width > bestWidth) {
            best = t;
            bestWidth = width;
        }
    }
    NSString *url = [best objectForKey:@"url"];
    return ([url isKindOfClass:[NSString class]] && url.length) ? url : nil;
}

// Upgrade a thumbnail URL to the largest variant that is actually available.
//
// YouTube serves exactly one size per name:
//   sddefault       640x480  (what list browsing uses, and what we ship today)
//   hqdefault       480x360  (always present)
//   maxresdefault  1280x720  (ABSENT for many videos -- ~3 in 8 in a sample)
//
// maxresdefault is the sharp one and is what the lock screen needs, but a
// missing maxres returns HTTP 404 with a 120x90 placeholder body, so a naive
// upgrade silently ships a blurry image -- which is why this previously looked
// "unreliable" and was skipped. The fix is not to avoid maxres but to detect
// the placeholder and fall back: LTLoadArtworkAtQuality does that, and only
// accepts a fetched image once it is at least kMinUsableArtWidth pixels wide.
//
// For non-i.ytimg URLs (lh3/ggpht avatars, which already carry a =wNNN-hNNN
// size parameter) just widen the existing size to the largest we ask for.
- (NSString *)highResThumbnailURL:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || urlString.length < 8) return urlString;
    // This only widens URLs that carry an explicit size parameter. Plain
    // i.ytimg.com URLs (".../sddefault.jpg") name their own size and are left
    // alone here -- artworkURLsForTrack: is what builds the real size ladder for
    // those, because a missing maxresdefault answers 404 with a 120x90
    // placeholder that has to be detected rather than trusted.
    //
    // Nothing to rewrite means return the input untouched: that is the common
    // case (any URL without an =wNN-hNN or /wNN-hNN segment), and this runs on
    // every cell dequeue. Caching the rest is worth it because the alternative is
    // a mutable copy, a two-element array literal and two full regex replacement
    // passes per call.
    if ([urlString rangeOfString:@"-h"].location == NSNotFound) return urlString;

    static NSCache *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 500;
    });
    NSString *hit = [cache objectForKey:urlString];
    if (hit) return hit;

    // The patterns are compiled once. Building an NSRegularExpression is an ICU
    // compile, and this runs for every cell dequeue.
    static NSRegularExpression *querySize = nil;   // =w1200-h1200
    static NSRegularExpression *pathSize = nil;    // /w1200-h1200
    static dispatch_once_t regexOnce;
    dispatch_once(&regexOnce, ^{
        querySize = [NSRegularExpression regularExpressionWithPattern:@"=w\\d+-h\\d+" options:0 error:nil];
        pathSize = [NSRegularExpression regularExpressionWithPattern:@"/w\\d+-h\\d+" options:0 error:nil];
    });
    NSMutableString *result = [urlString mutableCopy];
    NSArray *regexes = @[ querySize ?: [NSNull null], pathSize ?: [NSNull null] ];
    NSArray *templates = @[ @"=w1200-h1200", @"/w1200-h1200" ];
    for (NSUInteger i = 0; i < 2; i++) {
        NSRegularExpression *regex = [regexes objectAtIndex:i];
        if (regex == (id)[NSNull null]) continue;
        [regex replaceMatchesInString:result options:0 range:NSMakeRange(0, result.length)
                         withTemplate:[templates objectAtIndex:i]];
    }
    NSString *out = [result copy];
    [cache setObject:out forKey:urlString];
    return out;
}

// Candidate URLs for artwork, best first. Callers walk this until one yields a
// large-enough image. Exposed so the now-playing path can prefer quality while
// list cells keep using the cheap already-cached size.
- (NSArray *)artworkURLsForTrack:(LTTrack *)track {
    NSString *base = track.thumbnailURL;
    if (![base isKindOfClass:[NSString class]]) return [NSArray array];
    return [self artworkCandidateURLsForBaseURL:base];
}

// YouTube hands back two very different kinds of thumbnail URL and only one of
// them is a stable artwork source:
//
//   * i.ytimg.com/vi/<id>/hqdefault.jpg  - a plain, named, permanent size.
//   * i.ytimg.com/vi/<id>/hq720.jpg?sqp=..&rs=..  - a *signed* URL carrying an
//     expiry token. These decode fine once, then start answering with a body
//     that is not an image at all.
//
// Callers that only have a URL string used to load it directly and silently got
// nothing back when it was the signed form. Route those through the ladder so
// a dead signature costs one skipped request instead of an empty cell.
- (BOOL)isSignedYouTubeThumbURL:(NSString *)urlString {
    if (!urlString.length) return NO;
    if ([urlString rangeOfString:@"i.ytimg.com"].location == NSNotFound) return NO;
    if ([urlString rangeOfString:@"/vi/"].location == NSNotFound) return NO;
    // The named sizes are unsuffixed; anything carrying a query string is signed.
    return [urlString rangeOfString:@"?"].location != NSNotFound;
}

- (NSArray *)artworkCandidateURLsForBaseURL:(NSString *)base {
    NSMutableArray *urls = [NSMutableArray array];
    if (![base isKindOfClass:[NSString class]] || base.length < 8) return urls;

    NSString *wide = [self highResThumbnailURL:base];
    if ([wide isKindOfClass:[NSString class]] && wide.length) [urls addObject:wide];

    // i.ytimg.com named sizes, in descending preference.
    if ([base rangeOfString:@"i.ytimg.com"].location != NSNotFound &&
        [base rangeOfString:@"/vi/"].location != NSNotFound) {
        NSRange last = [base rangeOfString:@"/vi/" options:NSBackwardsSearch];
        if (last.location != NSNotFound) {
            NSString *prefix = [base substringToIndex:last.location + last.length];
            NSString *vid = [base substringFromIndex:last.location + last.length];
            // Strip any trailing /sddefault.jpg etc.
            NSRange slash = [vid rangeOfString:@"/" options:NSBackwardsSearch];
            if (slash.location != NSNotFound) vid = [vid substringToIndex:slash.location];
            for (NSString *name in @[ @"maxresdefault.jpg", @"hqdefault.jpg", @"sddefault.jpg" ]) {
                NSString *candidate = [NSString stringWithFormat:@"%@%@/%@", prefix, vid, name];
                if (![urls containsObject:candidate]) [urls addObject:candidate];
            }
        }
    }
    return urls;
}

- (LTBrowseKind)kindForBrowseId:(NSString *)browseId {
    if ([browseId hasPrefix:@"MPREb_"]) return LTBrowseKindAlbum;
    if ([browseId hasPrefix:@"VL"]) return LTBrowseKindPlaylist;
    return LTBrowseKindArtist;
}

- (void)applySubtitleRuns:(NSArray *)runs toTrack:(LTTrack *)track {
    NSArray *parts = [self filteredRuns:runs];
    if (!parts.count) return;
    track.artist = [parts objectAtIndex:0];
    if (parts.count >= 2) track.album = [parts objectAtIndex:1];
    if (parts.count >= 3) track.duration = [[self class] timeFromString:[parts objectAtIndex:2]];
}

+ (NSTimeInterval)timeFromString:(NSString *)string {
    if (!string.length) return 0;
    NSArray *parts = [string componentsSeparatedByString:@":"];
    if (parts.count == 2) {
        return [[parts objectAtIndex:0] intValue] * 60 + [[parts objectAtIndex:1] intValue];
    }
    if (parts.count == 3) {
        return [[parts objectAtIndex:0] intValue] * 3600 + [[parts objectAtIndex:1] intValue] * 60 + [[parts objectAtIndex:2] intValue];
    }
    return [string doubleValue];
}

- (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:LTYouTubeDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@end
