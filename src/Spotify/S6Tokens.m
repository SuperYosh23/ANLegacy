#import "S6Tokens.h"
#import "S6Session.h"
#import "S6Proto.h"
#import "S6Crypto.h"
#import "S6Settings.h"
#import "S6HTTPRequest.h"
#import "S6Utils.h"
#import "S6Common.h"

#include "mbedtls/sha1.h"
#include <unistd.h>

NSString * const S6ClientId = @"65b708073fc0480ea92a077233ca87bd";
NSString * const S6UserAgent = @"Spotify/124200290 Linux/0 (librespot-sixify)";
static NSString * const S6ClientVersion = @"1.2.52.442";
static NSString * const S6WebScopes = @"user-read-private,user-read-email,playlist-read-private,playlist-read-collaborative,"
    "playlist-modify-public,playlist-modify-private,user-library-read,user-library-modify,user-follow-read,user-follow-modify,"
    "user-top-read,user-read-recently-played,user-read-playback-state,user-modify-playback-state,user-read-currently-playing,"
    "user-read-playback-position,streaming,app-remote-control,ugc-image-upload";

NSData *S6SyncRequest(NSString *method, NSString *url, NSDictionary *headers, NSData *body, NSInteger *status,
                      NSDictionary **responseHeaders, NSError **error)
{
    NSURL *u = [NSURL URLWithString:url];
    if (!u) { if (error) *error = S6MakeError(S6ErrorBadResponse, [NSString stringWithFormat:L(@"Bad address: %@"), url ?: @""]); return nil; }
    for (int hop = 0; hop < 4; hop++) {
        S6HTTPRequest *r = [[S6HTTPRequest alloc] initWithMethod:method URL:u];
        NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: [NSDictionary dictionary]];
        if (![h objectForKey:@"User-Agent"]) [h setObject:S6UserAgent forKey:@"User-Agent"];
        r.headers = h;
        r.body = body;
        r.verifyTLS = [S6Settings verifyTLS];
        r.connectTimeout = 15;
        r.readTimeout = 30;
        __block NSError *failure = nil;
        r.onComplete = ^(NSError *e) { failure = e; };
        [r runSynchronously];
        if (failure) { if (error) *error = failure; return nil; }
        NSInteger s = r.statusCode;
        NSString *location = [r.responseHeaders objectForKey:@"location"];
        if (s >= 300 && s < 400 && location.length) {
            u = [[NSURL URLWithString:location relativeToURL:u] absoluteURL];
            if ([method isEqualToString:@"POST"] && s != 307 && s != 308) { method = @"GET"; body = nil; }
            continue;
        }
        if (status) *status = s;
        if (responseHeaders) *responseHeaders = r.responseHeaders;
        return r.responseBody ?: [NSData data];
    }
    if (error) *error = S6MakeError(S6ErrorBadResponse, L(@"Too many redirects."));
    return nil;
}

static inline uint64_t S6BE64(const uint8_t *p)
{
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v = (v << 8) | p[i];
    return v;
}

static inline void S6PutBE64(uint8_t *p, uint64_t v)
{
    for (int i = 7; i >= 0; i--) { p[i] = (uint8_t)v; v >>= 8; }
}

// Spotify's proof of work: a 16-byte suffix whose SHA-1 together with the prefix ends in `length` zero bits
// (as librespot's util::solve_hash_cash). Returns how long it took, or a negative value when 5 s were not enough.
static NSTimeInterval S6SolveHashcash(NSData *context, NSData *prefix, int length, uint8_t suffix[16])
{
    uint8_t md[20];
    mbedtls_sha1(context.bytes, context.length, md);
    uint64_t target = S6BE64(md + 12);
    NSMutableData *buf = [NSMutableData dataWithData:prefix];
    [buf increaseLengthBy:16];
    uint8_t *s = (uint8_t *)buf.mutableBytes + prefix.length;
    NSDate *start = [NSDate date];
    for (uint64_t counter = 0; ; counter++) {
        if ((counter & 0x3FF) == 0 && -[start timeIntervalSinceNow] > 5) return -1;
        S6PutBE64(s, target + counter);
        S6PutBE64(s + 8, counter);
        mbedtls_sha1(buf.bytes, buf.length, md);
        uint64_t v = S6BE64(md + 12);
        int zeros = v ? __builtin_ctzll(v) : 64;
        if (zeros >= length) {
            memcpy(suffix, s, 16);
            return -[start timeIntervalSinceNow];
        }
    }
}

@implementation S6Tokens {
    NSString *_clientToken;
    NSDate *_clientTokenExpiry;
    NSString *_accessToken;
    NSDate *_accessTokenExpiry;
    NSString *_webToken;
    NSDate *_webTokenExpiry;
    NSString *_webTokenSource;
    NSLock *_lock;
}

+ (instancetype)shared
{
    static S6Tokens *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tokens = [[S6Tokens alloc] init]; });
    return tokens;
}

- (instancetype)init
{
    if ((self = [super init])) _lock = [[NSLock alloc] init];
    return self;
}

- (void)reset
{
    [_lock lock];
    _accessToken = nil;
    _webToken = nil;
    [_lock unlock];
}

- (void)invalidateAccessToken { [_lock lock]; _accessToken = nil; [_lock unlock]; }
- (void)invalidateWebToken { [_lock lock]; _webToken = nil; [_lock unlock]; }

#pragma mark - Client token

- (NSData *)clientTokenRequestBodyFor:(NSString *)clientId
{
    S6ProtoWriter *linux = [S6ProtoWriter writer];
    [linux string:@"Linux" field:1];          // system_name
    [linux string:@"6.1.21-v7+" field:2];     // system_release
    [linux string:@"12" field:3];             // system_version
    [linux string:@"arm" field:4];            // hardware
    S6ProtoWriter *platform = [S6ProtoWriter writer];
    [platform message:linux field:5];         // desktop_linux
    S6ProtoWriter *connectivity = [S6ProtoWriter writer];
    [connectivity message:platform field:1];
    [connectivity string:[S6Settings deviceId] field:2];
    S6ProtoWriter *clientData = [S6ProtoWriter writer];
    [clientData string:S6ClientVersion field:1];
    [clientData string:clientId field:2];
    [clientData message:connectivity field:3];
    S6ProtoWriter *request = [S6ProtoWriter writer];
    [request varint:1 field:1];               // REQUEST_CLIENT_DATA_REQUEST
    [request message:clientData field:2];
    return request.data;
}

- (NSString *)clientTokenWithError:(NSError **)error
{
    [_lock lock];
    if (_clientToken && [_clientTokenExpiry timeIntervalSinceNow] > 60) { NSString *t = _clientToken; [_lock unlock]; return t; }
    [_lock unlock];
    int64_t lifetime = 0;
    NSString *token = [self fetchClientTokenFor:S6ClientId lifetime:&lifetime error:error];
    if (token) {
        [_lock lock];
        _clientToken = token;
        _clientTokenExpiry = [NSDate dateWithTimeIntervalSinceNow:lifetime > 0 ? lifetime : 7200];
        [_lock unlock];
    }
    return token;
}

// One client token from Spotify, after its hash cash puzzle when it sets one
- (NSString *)fetchClientTokenFor:(NSString *)clientId lifetime:(int64_t *)lifetime error:(NSError **)error
{
    NSDictionary *headers = @{ @"Accept": @"application/x-protobuf", @"Content-Type": @"application/x-protobuf" };
    NSData *body = [self clientTokenRequestBodyFor:clientId];
    for (int attempt = 0; attempt < 3; attempt++) {
        NSInteger status = 0;
        NSData *response = S6SyncRequest(@"POST", @"https://clienttoken.spotify.com/v1/clienttoken", headers, body, &status, NULL, error);
        if (!response) return nil;
        if (status != 200) {
            S6Log(@"client token: HTTP %ld", (long)status);
            if (error) *error = S6MakeError(status, [NSString stringWithFormat:L(@"Spotify answered with error %ld."), (long)status]);
            return nil;
        }
        uint64_t type = S6ProtoVarint(response, 1, 0);
        if (type == 1) {
            NSData *granted = S6ProtoBytes(response, 2);
            NSString *token = S6ProtoString(granted, 1);
            int64_t refresh = (int64_t)S6ProtoVarint(granted, 3, 7200);
            if (!token.length) break;
            if (lifetime) *lifetime = refresh;
            return token;
        }
        if (type == 2) {
            // a hash cash challenge first (the platforms Spotify cares about get one)
            NSData *challenges = S6ProtoBytes(response, 3);
            NSString *state = S6ProtoString(challenges, 1) ?: @"";
            NSData *challenge = S6ProtoBytes(challenges, 2);
            NSData *parameters = S6ProtoBytes(challenge, 4);
            int length = (int)S6ProtoVarint(parameters, 1, 0);
            NSData *prefix = [S6Crypto dataFromHex:S6ProtoString(parameters, 2) ?: @""];
            uint8_t suffix[16];
            if (!prefix || S6SolveHashcash([NSData data], prefix, length, suffix) < 0) continue;
            S6ProtoWriter *hashCash = [S6ProtoWriter writer];
            [hashCash string:[S6Crypto hexUpper:[NSData dataWithBytes:suffix length:16]] field:1];
            S6ProtoWriter *answer = [S6ProtoWriter writer];
            [answer varint:3 field:1];             // CHALLENGE_HASH_CASH
            [answer message:hashCash field:4];
            S6ProtoWriter *answers = [S6ProtoWriter writer];
            [answers string:state field:1];
            [answers message:answer field:2];
            S6ProtoWriter *request = [S6ProtoWriter writer];
            [request varint:2 field:1];            // REQUEST_CHALLENGE_ANSWERS_REQUEST
            [request message:answers field:3];
            body = request.data;
            continue;
        }
        break;
    }
    if (error) *error = S6MakeError(S6ErrorAuth, L(@"Spotify did not hand out a client token."));
    return nil;
}

#pragma mark - Access token (login5)

- (NSString *)accessTokenWithError:(NSError **)error
{
    [_lock lock];
    if (_accessToken && [_accessTokenExpiry timeIntervalSinceNow] > 60) { NSString *t = _accessToken; [_lock unlock]; return t; }
    [_lock unlock];
    if (![[S6Session shared] waitUntilReady:20 error:error]) return nil;
    NSString *clientToken = [self clientTokenWithError:error];
    if (!clientToken) return nil;
    int64_t lifetime = 0;
    NSString *token = [self fetchLogin5TokenFor:S6ClientId clientToken:clientToken lifetime:&lifetime error:error];
    if (token) {
        [_lock lock];
        _accessToken = token;
        _accessTokenExpiry = [NSDate dateWithTimeIntervalSinceNow:lifetime > 0 ? lifetime : 3600];
        [_lock unlock];
    }
    return token;
}

// One access token from login5 with the stored credentials, after its hash cash puzzles
- (NSString *)fetchLogin5TokenFor:(NSString *)clientId clientToken:(NSString *)clientToken lifetime:(int64_t *)lifetime error:(NSError **)error
{
    S6ProtoWriter *clientInfo = [S6ProtoWriter writer];
    [clientInfo string:clientId field:1];
    [clientInfo string:[S6Settings deviceId] field:2];
    S6ProtoWriter *stored = [S6ProtoWriter writer];
    [stored string:[S6Settings username] field:1];
    [stored bytes:[S6Settings authData] field:2];
    NSData *loginContext = nil;
    S6ProtoWriter *solutions = nil;
    NSDictionary *headers = @{ @"Accept": @"application/x-protobuf", @"Content-Type": @"application/x-protobuf", @"client-token": clientToken };

    for (int attempt = 0; attempt < 3; attempt++) {
        S6ProtoWriter *request = [S6ProtoWriter writer];
        [request message:clientInfo field:1];
        if (loginContext) [request bytes:loginContext field:2];
        if (solutions) [request message:solutions field:3];
        [request message:stored field:100];
        NSInteger status = 0;
        NSData *response = S6SyncRequest(@"POST", @"https://login5.spotify.com/v3/login", headers, request.data, &status, NULL, error);
        if (!response) return nil;
        if (status != 200) {
            S6Log(@"login5: HTTP %ld", (long)status);
            if (error) *error = S6MakeError(status, [NSString stringWithFormat:L(@"Spotify answered with error %ld."), (long)status]);
            return nil;
        }
        NSData *ok = S6ProtoBytes(response, 1);
        if (ok) {
            NSString *token = S6ProtoString(ok, 2);
            int64_t expires = (int64_t)S6ProtoVarint(ok, 4, 3600);
            if (!token.length) break;
            if (lifetime) *lifetime = expires;
            return token;
        }
        if (S6ProtoHas(response, 2)) {
            uint64_t code = S6ProtoVarint(response, 2, 0);
            if (code == 4 || code == 6) { sleep(3); continue; }   // TIMEOUT, TOO_MANY_ATTEMPTS
            if (error) *error = S6MakeError(S6ErrorAuth, [NSString stringWithFormat:L(@"Spotify refused the login (login5 error %llu)."), code]);
            return nil;
        }
        NSData *challenges = S6ProtoBytes(response, 3);
        if (!challenges) break;
        loginContext = S6ProtoBytes(response, 5);
        solutions = [S6ProtoWriter writer];
        for (NSData *challenge in S6ProtoAllBytes(challenges, 1)) {
            NSData *hashcash = S6ProtoBytes(challenge, 1);
            if (!hashcash) {
                if (S6ProtoHas(challenge, 2)) {
                    if (error) *error = S6MakeError(S6ErrorAuth, L(@"Spotify wants an extra confirmation that Sixify cannot give."));
                    return nil;
                }
                continue;
            }
            uint8_t suffix[16];
            NSTimeInterval took = S6SolveHashcash(loginContext ?: [NSData data], S6ProtoBytes(hashcash, 1) ?: [NSData data],
                                                  (int)S6ProtoVarint(hashcash, 2, 0), suffix);
            if (took < 0) continue;
            S6ProtoWriter *duration = [S6ProtoWriter writer];
            [duration varint:(uint64_t)took field:1];
            [duration varint:(uint64_t)((took - floor(took)) * 1e9) field:2];
            S6ProtoWriter *solution = [S6ProtoWriter writer];
            [solution bytes:[NSData dataWithBytes:suffix length:16] field:1];
            [solution message:duration field:2];
            S6ProtoWriter *wrapped = [S6ProtoWriter writer];
            [wrapped message:solution field:1];
            [solutions message:wrapped field:1];
        }
    }
    if (error) *error = S6MakeError(S6ErrorAuth, L(@"Spotify did not hand out an access token."));
    return nil;
}

#pragma mark - Web API token

- (NSString *)webTokenWithError:(NSError **)error
{
    [_lock lock];
    if (_webToken && [_webTokenExpiry timeIntervalSinceNow] > 60) { NSString *t = _webToken; [_lock unlock]; return t; }
    [_lock unlock];

    // keymaster over Mercury: a token with the Web API scopes
    NSString *uri = [NSString stringWithFormat:@"hm://keymaster/token/authenticated?scope=%@&client_id=%@&device_id=%@",
                     S6WebScopes, S6ClientId, [S6Settings deviceId]];
    NSInteger status = 0;
    NSError *mercuryError = nil;
    NSArray *parts = [[S6Session shared] mercuryGet:uri status:&status error:&mercuryError];
    NSDictionary *json = parts.count ? S6Dict([S6Utils JSONObjectFromData:[parts objectAtIndex:0]]) : nil;
    NSString *token = S6Str([json objectForKey:@"accessToken"]);
    if (token.length) {
        NSInteger expires = S6Int([json objectForKey:@"expiresIn"]);
        [_lock lock];
        _webToken = token;
        _webTokenExpiry = [NSDate dateWithTimeIntervalSinceNow:expires > 0 ? expires : 3600];
        _webTokenSource = @"keymaster";
        [_lock unlock];
        return token;
    }
    S6Log(@"keymaster token failed (%@), using the login5 token for the Web API", mercuryError.localizedDescription ?: [NSString stringWithFormat:@"status %ld", (long)status]);
    token = [self accessTokenWithError:error];
    if (token) {
        [_lock lock];
        _webToken = token;
        _webTokenExpiry = _accessTokenExpiry;
        _webTokenSource = @"login5";
        [_lock unlock];
    }
    return token;
}

// Debug: which client ids login5 hands tokens out for, and what the public Web API says to each (logs only the
// status and, for errors, the start of the answer)
- (void)debugTokenTest
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *ids = @[ S6ClientId, @"d8a5ed958d274c2e8ee717e6a4b0971d", @"9a8d2f0ce77a4e248bb71fefcb557637", @"58bd3c95768941ea9eb4350aaa033eb3" ];
        for (NSString *cid in ids) {
            NSError *e = nil;
            int64_t life = 0;
            NSString *ct = [self fetchClientTokenFor:cid lifetime:&life error:&e];
            if (!ct) { S6Log(@"tokentest %@: client token failed: %@", cid, e.localizedDescription); continue; }
            NSString *at = [self fetchLogin5TokenFor:cid clientToken:ct lifetime:&life error:&e];
            if (!at) { S6Log(@"tokentest %@: login5 failed: %@", cid, e.localizedDescription); continue; }
            for (NSString *url in @[ @"https://api.spotify.com/v1/me", @"https://api.spotify.com/v1/search?q=daft%20punk&type=track&limit=1" ]) {
                NSInteger status = 0;
                NSDictionary *h = nil;
                NSData *body = S6SyncRequest(@"GET", url, @{ @"Authorization": [@"Bearer " stringByAppendingString:at], @"Accept": @"application/json" },
                                             nil, &status, &h, &e);
                NSString *text = body ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : e.localizedDescription;
                S6Log(@"tokentest %@: %@ -> %ld, retry-after %@: %@", [cid substringToIndex:6], [url substringFromIndex:26], (long)status,
                      [h objectForKey:@"retry-after"] ?: @"-", status == 200 ? [NSString stringWithFormat:@"ok (%lu bytes)", (unsigned long)body.length]
                                                               : [S6Utils truncate:[text stringByReplacingOccurrencesOfString:@"\n" withString:@" "] to:160]);
            }
        }
        S6Log(@"tokentest done");
    });
}

- (NSString *)debugState
{
    [_lock lock];
    NSString *s = [NSString stringWithFormat:@"client token %@, access token %@, web token %@ (%@)",
                   _clientToken ? @"yes" : @"no", _accessToken ? @"yes" : @"no", _webToken ? @"yes" : @"no", _webTokenSource ?: @"-"];
    [_lock unlock];
    return s;
}

@end
