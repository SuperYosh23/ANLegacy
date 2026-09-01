#import "LTYouTubeClient.h"
#import "LTPlaylistStore.h"
#import "LTLog.h"
#import <CommonCrypto/CommonDigest.h>

NSString *const LTAPIKey = @"AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";
NSString *const LTBrowserUserAgent = @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36";

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

@interface LTYouTubeClient ()
@property (nonatomic, strong) NSCache *imageCache;
@end

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
        _imageCache = [[NSCache alloc] init];
    }
    return self;
}

#pragma mark - Networking

- (void)postToHost:(NSString *)host path:(NSString *)path body:(NSDictionary *)body
        completion:(void (^)(id json, NSError *error))completion {
    NSString *urlString = [NSString stringWithFormat:@"https://%@/youtubei/v1/%@?key=%@&prettyPrint=false",
                           host, path, LTAPIKey];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:30.0];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:[NSString stringWithFormat:@"https://%@/", host] forHTTPHeaderField:@"Referer"];

    NSError *serializeError = nil;
    NSData *payload = [NSJSONSerialization dataWithJSONObject:body options:0 error:&serializeError];
    if (!payload) {
        if (completion) completion(nil, serializeError);
        return;
    }
    [request setHTTPBody:payload];

    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            if (completion) completion(nil, connectionError);
            return;
        }
        NSError *parseError = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (!obj) {
            if (completion) completion(nil, parseError);
            return;
        }
        [self ingestVisitorData:obj];
        if (completion) completion(obj, nil);
    }];
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
        NSDictionary *info = [self headerInfo:json];
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
        NSDictionary *info = [self headerInfo:json];
        NSArray *tracks = [self tracksFromPlaylistShelf:json];
        if (completion) completion(info, tracks, nil);
    }];
}

- (void)browseArtist:(NSString *)browseId
          completion:(void (^)(NSDictionary *info, NSArray *topSongs, NSArray *albums, NSError *error))completion {
    NSDictionary *body = @{@"context": [self webRemixContext], @"browseId": browseId};
    [self postToHost:@"music.youtube.com" path:@"browse" body:body completion:^(id json, NSError *error) {
        if (error || !json) {
            if (completion) completion(nil, nil, nil, error);
            return;
        }
        NSDictionary *info = [self headerInfo:json];
        NSArray *topSongs = [self artistTopSongs:json];
        NSArray *albums = [self artistAlbums:json];
        if (completion) completion(info, topSongs, albums, nil);
    }];
}

#pragma mark - Trending

- (void)fetchTrendingSongsWithCompletion:(void (^)(NSArray *tracks, NSError *error))completion {
    NSDictionary *body = @{@"context": [self webRemixContext], @"browseId": @"FEmusic_charts"};
    __weak LTYouTubeClient *weakSelf = self;
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
        NSString *title = [self textFromRuns:[renderer objectForKey:@"title"][@"runs"]];
        NSString *browseId = LTPath(renderer, @"navigationEndpoint", @"browseEndpoint", @"browseId", nil);
        if (![browseId isKindOfClass:[NSString class]] || !browseId.length) return;
        if (!fallback && [browseId hasPrefix:@"VL"]) fallback = browseId;
        if (!trending && [title rangeOfString:@"Trending"].location != NSNotFound) trending = browseId;
    }];
    if (trending.length) return trending;
    return fallback ?: @"";
}

- (NSDictionary *)headerInfo:(NSDictionary *)json {
    NSString *title = nil, *subtitle = nil, *thumb = nil;

    id immersive = LTPath(json, @"header", @"musicImmersiveHeaderRenderer", nil);
    if ([immersive isKindOfClass:[NSDictionary class]]) {
        title = [self textFromRuns:[immersive objectForKey:@"title"][@"runs"]];
        thumb = [self thumbnailFromHeader:immersive];
    }

    if (!title) {
        NSArray *sections = LTPath(json, @"contents", @"singleColumnBrowseResultsRenderer", @"tabs", @0,
                                   @"tabRenderer", @"content", @"sectionListRenderer", @"contents", nil);
        for (id section in sections) {
            if (![section isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *header = [section objectForKey:@"musicResponsiveHeaderRenderer"];
            if (!header) continue;
            title = [self textFromRuns:[header objectForKey:@"title"][@"runs"]];
            subtitle = [self textFromRuns:[header objectForKey:@"subtitle"][@"runs"]];
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
            title = [self textFromRuns:[detail objectForKey:@"title"][@"runs"]];
            subtitle = [self subtitleForDetailHeader:detail];
            thumb = [self thumbnailFromHeader:detail];
        }
    }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (title.length) [info setObject:title forKey:@"title"];
    if (subtitle.length) [info setObject:subtitle forKey:@"subtitle"];
    if (thumb.length) [info setObject:thumb forKey:@"thumbnail"];
    return info;
}

- (NSString *)subtitleForDetailHeader:(NSDictionary *)detail {
    NSMutableArray *parts = [NSMutableArray array];
    NSArray *s1 = [detail objectForKey:@"subtitle"][@"runs"];
    for (id run in s1) {
        if ([run isKindOfClass:[NSDictionary class]]) {
            NSString *text = [run objectForKey:@"text"];
            if (text.length) [parts addObject:text];
        }
    }
    id affects = [detail objectForKey:@"subtitle"][@"content"];
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
        NSDictionary *fc = [fixed objectAtIndex:0][@"musicResponsiveListItemFixedColumnRenderer"];
        NSArray *druns = [fc objectForKey:@"text"][@"runs"];
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

- (NSArray *)artistTopSongs:(NSDictionary *)json {
    NSMutableArray *tracks = [NSMutableArray array];
    [self enumerateRenderersIn:json key:@"musicShelfRenderer" block:^(NSDictionary *shelf) {
        NSString *shelfTitle = [self textFromRuns:[shelf objectForKey:@"title"][@"runs"]];
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
            bi.title = [self textFromRuns:[it objectForKey:@"title"][@"runs"]];
            bi.subtitle = [self textFromRuns:[it objectForKey:@"subtitle"][@"runs"]];
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
    __weak LTYouTubeClient *weakSelf = self;
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
    __weak LTYouTubeClient *weakSelf = self;
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
    if (cw >= W && ch >= H) return image;
    if (allowCenterCrop && cw != ch) {
        if (cw > ch) {
            left += (cw - ch) / 2;
            cw = ch;
        } else {
            top += (ch - cw) / 2;
            ch = cw;
        }
    }

    CGImageRef sub = CGImageCreateWithImageInRect(cg, CGRectMake((CGFloat)left, (CGFloat)top, (CGFloat)cw, (CGFloat)ch));
    if (!sub) return image;
    UIImage *trimmed = [UIImage imageWithCGImage:sub scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(sub);
    return trimmed ?: image;
}

- (void)loadImageWithURL:(NSString *)urlString
              completion:(void (^)(UIImage *image))completion {
    if (!urlString.length) {
        if (completion) completion(nil);
        return;
    }
    LTLog(@"IMG load url=%@", urlString);
    UIImage *cached = [self.imageCache objectForKey:urlString];
    if (cached) {
        if (completion) completion(cached);
        return;
    }
    NSString *diskPath = [self diskCachePathForURL:urlString];
    UIImage *diskImage = [UIImage imageWithContentsOfFile:diskPath];
    if (diskImage) {
        LTLog(@"IMG disk-hit url=%@", urlString);
        diskImage = LTTrimmedArtworkImage(diskImage, [urlString rangeOfString:@"i.ytimg.com"].location != NSNotFound);
        [self.imageCache setObject:diskImage forKey:urlString];
        if (completion) completion(diskImage);
        return;
    }
    NSString *fallback = nil;
    if ([urlString hasSuffix:@"maxresdefault.jpg"]) {
        fallback = [urlString stringByReplacingOccurrencesOfString:@"maxresdefault.jpg"
                                                        withString:@"sddefault.jpg"];
    }
    [self fetchImageAtURL:urlString fallbackURL:fallback diskPath:diskPath cacheKey:urlString completion:completion];
}

- (void)fetchImageAtURL:(NSString *)urlString
            fallbackURL:(NSString *)fallbackURL
               diskPath:(NSString *)diskPath
              cacheKey:(NSString *)cacheKey
             completion:(void (^)(UIImage *image))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                            cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                                        timeoutInterval:30.0];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];

    void (^handleResponse)(NSData *, NSError *) = ^(NSData *data, NSError *connectionError) {
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
            if (completion) completion(nil);
            return;
        }
        image = LTTrimmedArtworkImage(image, [cacheKey rangeOfString:@"i.ytimg.com"].location != NSNotFound);
        [self.imageCache setObject:image forKey:cacheKey];
        NSData *encoded = UIImageJPEGRepresentation(image, 0.85);
        if (encoded) [encoded writeToFile:diskPath atomically:YES];
        // Always call completion on the main thread so UI updates work
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(image);
        });
    };

    // Use NSURLSession on iOS 7+ (NSURLConnection is deprecated and silently fails on iOS 10+)
    if (NSClassFromString(@"NSURLSession")) {
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                handleResponse(data, error);
            }];
        [task resume];
    } else {
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                               completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
            handleResponse(data, connectionError);
        }];
    }
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
    id runs = [col objectForKey:@"text"][@"runs"];
    if ([runs isKindOfClass:[NSArray class]]) return runs;
    id simple = [col objectForKey:@"text"][@"simpleText"];
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

- (NSString *)highResThumbnailURL:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || urlString.length < 8) return urlString;
    // i.ytimg.com paths are left alone: sddefault is already disk-cached from
    // list browsing and trims to a clean square, while maxresdefault fetches
    // proved unreliable on device.
    NSMutableString *result = [urlString mutableCopy];
    NSArray *patterns = @[
        @[@"=w\\d+-h\\d+", @"=w1200-h1200"],
        @[@"/w\\d+-h\\d+", @"/w1200-h1200"],
    ];
    for (NSArray *pair in patterns) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:[pair objectAtIndex:0]
                                                                               options:0 error:nil];
        [regex replaceMatchesInString:result options:0 range:NSMakeRange(0, result.length)
                         withTemplate:[pair objectAtIndex:1]];
    }
    return result;
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
