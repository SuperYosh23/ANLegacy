#import "S6SpClient.h"
#import "S6Session.h"
#import "S6Tokens.h"
#import "S6Proto.h"
#import "S6Crypto.h"
#import "S6Utils.h"
#import "S6Common.h"

@implementation S6SpClient

+ (dispatch_queue_t)queue
{
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("com.samcejko.sixify.spclient", NULL /* was DISPATCH_QUEUE_CONCURRENT */); });
    return q;
}

+ (NSData *)request:(NSString *)method path:(NSString *)path body:(NSData *)body contentType:(NSString *)contentType
             accept:(NSString *)accept status:(NSInteger *)status error:(NSError **)error
{
    return [self request:method path:path body:body contentType:contentType accept:accept headers:nil status:status error:error];
}

+ (NSData *)request:(NSString *)method path:(NSString *)path body:(NSData *)body contentType:(NSString *)contentType
             accept:(NSString *)accept headers:(NSDictionary *)extraHeaders status:(NSInteger *)status error:(NSError **)error
{
    S6Session *session = [S6Session shared];
    if (![session waitUntilReady:20 error:error]) return nil;
    NSMutableString *url = [NSMutableString stringWithFormat:@"https://%@%@", session.spclientHost ?: @"spclient.wg.spotify.com:443", path];
    if ([path rangeOfString:@"context-resolve"].location == NSNotFound && [path rangeOfString:@"connect-state"].location == NSNotFound) {
        // (as librespot: the "metrics" of every request and a salt against caches)
        [url appendFormat:@"%@product=0&country=%@&salt=%u", [path rangeOfString:@"?"].location == NSNotFound ? @"?" : @"&",
         session.country ?: @"US", arc4random()];
    }
    for (int attempt = 0; attempt < 2; attempt++) {
        NSString *token = [[S6Tokens shared] accessTokenWithError:error];
        if (!token) return nil;
        NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithDictionary:@{ @"Authorization": [@"Bearer " stringByAppendingString:token] }];
        NSString *clientToken = [[S6Tokens shared] clientTokenWithError:NULL];
        if (clientToken) [headers setObject:clientToken forKey:@"client-token"];
        if (accept) [headers setObject:accept forKey:@"Accept"];
        if (contentType) [headers setObject:contentType forKey:@"Content-Type"];
        if (extraHeaders) [headers addEntriesFromDictionary:extraHeaders];
        NSInteger s = 0;
        NSData *data = S6SyncRequest(method, url, headers, body, &s, NULL, error);
        if (!data) return nil;
        if (s == 401 && attempt == 0) { [[S6Tokens shared] invalidateAccessToken]; continue; }
        if (status) *status = s;
        if (s >= 400) {
            if (s != 404) {
                NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
                S6Log(@"spclient %@ %@: HTTP %ld %@", method, path, (long)s, [S6Utils truncate:[text stringByReplacingOccurrencesOfString:@"\n" withString:@" "] to:300]);
            }
            if (error) *error = S6MakeError(s, [NSString stringWithFormat:L(@"Spotify answered with error %ld."), (long)s]);
            return nil;
        }
        return data;
    }
    if (error) *error = S6MakeError(401, L(@"Spotify did not accept the access token."));
    return nil;
}

+ (NSData *)extendedMetadataFor:(NSString *)uri kind:(uint64_t)kind error:(NSError **)error
{
    S6ProtoWriter *query = [S6ProtoWriter writer];
    [query varint:kind field:1];
    S6ProtoWriter *entity = [S6ProtoWriter writer];
    [entity string:uri field:1];
    [entity message:query field:2];
    S6ProtoWriter *request = [S6ProtoWriter writer];
    [request message:entity field:2];
    NSData *response = [self request:@"POST" path:@"/extended-metadata/v0/extended-metadata" body:request.data
                         contentType:@"application/x-protobuf" accept:@"application/x-protobuf" status:NULL error:error];
    if (!response) return nil;
    NSData *array = S6ProtoBytes(response, 2);           // EntityExtensionDataArray
    NSData *data = S6ProtoBytes(array, 3);               // EntityExtensionData
    NSData *header = S6ProtoBytes(data, 1);
    uint64_t code = header ? S6ProtoVarint(header, 1, 200) : 200;
    NSData *any = S6ProtoBytes(data, 3);                 // google.protobuf.Any
    NSData *value = S6ProtoBytes(any, 2);
    if (!value.length) {
        if (error) *error = S6MakeError(code == 404 ? S6ErrorRestricted : S6ErrorAPI,
                                        code == 404 ? L(@"This song is not available.") : [NSString stringWithFormat:L(@"Spotify answered with error %ld."), (long)code]);
        return nil;
    }
    return value;
}

+ (NSData *)trackMetadata:(NSData *)gid error:(NSError **)error
{
    return [self extendedMetadataFor:[@"spotify:track:" stringByAppendingString:S6Base62FromGid(gid) ?: @""] kind:10 error:error];
}

+ (NSData *)episodeMetadata:(NSData *)gid error:(NSError **)error
{
    return [self extendedMetadataFor:[@"spotify:episode:" stringByAppendingString:S6Base62FromGid(gid) ?: @""] kind:12 error:error];
}

+ (NSArray *)cdnURLsForFile:(NSData *)fileId error:(NSError **)error
{
    NSString *path = [NSString stringWithFormat:@"/storage-resolve/files/audio/interactive/%@", [S6Crypto hex:fileId]];
    NSData *response = [self request:@"GET" path:path body:nil contentType:nil accept:@"application/x-protobuf" status:NULL error:error];
    if (!response) return nil;
    uint64_t result = S6ProtoVarint(response, 1, 0);
    NSMutableArray *urls = [NSMutableArray array];
    for (NSData *u in S6ProtoAllBytes(response, 2)) {
        NSString *s = [[NSString alloc] initWithData:u encoding:NSUTF8StringEncoding];
        if (s.length) [urls addObject:s];
    }
    if (result != 0 || !urls.count) {
        if (error) *error = S6MakeError(S6ErrorRestricted, result == 3 ? L(@"This song is restricted.") : L(@"Spotify did not say where the song can be downloaded."));
        return nil;
    }
    return urls;
}

+ (void)lyricsForTrack:(NSString *)trackId completion:(void (^)(NSDictionary *, NSError *))completion
{
    dispatch_async([self queue], ^{
        NSError *error = nil;
        NSString *path = [NSString stringWithFormat:@"/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", trackId];
        NSData *data = [self request:@"GET" path:path body:nil contentType:nil accept:@"application/json" status:NULL error:&error];
        NSDictionary *json = data ? S6Dict([S6Utils JSONObjectFromData:data]) : nil;
        if (data && !json && !error) error = S6MakeError(S6ErrorBadResponse, L(@"No lyrics for this song."));
        dispatch_async(dispatch_get_main_queue(), ^{ completion(json, error); });
    });
}

+ (void)radioForURI:(NSString *)uri completion:(void (^)(NSArray *, NSError *))completion
{
    dispatch_async([self queue], ^{
        NSError *error = nil;
        NSString *path = [NSString stringWithFormat:@"/radio-apollo/v3/stations/%@?autoplay=true&count=50", uri];
        NSData *data = [self request:@"GET" path:path body:nil contentType:nil accept:@"application/json" status:NULL error:&error];
        NSDictionary *json = data ? S6Dict([S6Utils JSONObjectFromData:data]) : nil;
        NSMutableArray *uris = [NSMutableArray array];
        for (id t in S6Arr([json objectForKey:@"tracks"])) {
            NSString *u = S6Str([S6Dict(t) objectForKey:@"uri"]);
            if ([u hasPrefix:@"spotify:track:"]) [uris addObject:u];
        }
        if (!uris.count && !error) error = S6MakeError(S6ErrorAPI, L(@"No radio for this."));
        dispatch_async(dispatch_get_main_queue(), ^{ completion(uris, error); });
    });
}

@end
