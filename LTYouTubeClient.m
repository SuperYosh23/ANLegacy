#import "LTYouTubeClient.h"
#import "LTLog.h"

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
        track.thumbnailURL = [self thumbnailFromItem:item];
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

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (title.length) [info setObject:title forKey:@"title"];
    if (subtitle.length) [info setObject:subtitle forKey:@"subtitle"];
    if (thumb.length) [info setObject:thumb forKey:@"thumbnail"];
    return info;
}

- (NSString *)thumbnailFromHeader:(NSDictionary *)header {
    NSArray *thumbs = LTPath(header, @"thumbnail", @"musicThumbnailRenderer", @"thumbnail", @"thumbnails", nil);
    if (![thumbs isKindOfClass:[NSArray class]] || thumbs.count == 0) return nil;
    id last = [thumbs lastObject];
    if ([last isKindOfClass:[NSDictionary class]]) {
        return [last objectForKey:@"url"];
    }
    return nil;
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
    track.thumbnailURL = [self thumbnailFromItem:item];

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
            if ([thumbs isKindOfClass:[NSArray class]] && thumbs.count) {
                bi.thumbnailURL = [[thumbs lastObject] objectForKey:@"url"];
            }
            [albums addObject:bi];
        }
    }];
    return albums;
}

#pragma mark - Player

- (void)streamURLForVideo:(NSString *)videoId
               completion:(void (^)(NSString *streamURL, BOOL muxedStream, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, NO, [self errorWithCode:1 message:@"Missing video id"]);
        return;
    }
    __weak LTYouTubeClient *weakSelf = self;
    [self fetchStreamURLWithContext:[self androidVRContext]
                             clientName:@"ANDROID_VR"
                                videoId:videoId
                             completion:^(NSString *streamURL, BOOL muxed, NSError *vrError) {
        if (streamURL.length) {
            if (completion) completion(streamURL, muxed, nil);
            return;
        }
        LTLog(@"STREAM falling back to IOS client for %@", videoId);
        [weakSelf fetchStreamURLWithContext:[weakSelf iosContext]
                                 clientName:@"IOS"
                                    videoId:videoId
                                 completion:^(NSString *iosURL, BOOL iosMuxed, NSError *iosError) {
            if (iosURL.length) {
                if (completion) completion(iosURL, iosMuxed, nil);
                return;
            }
            LTLog(@"STREAM falling back to ANDROID client for %@", videoId);
            [weakSelf fetchStreamURLWithContext:[weakSelf androidContext]
                                     clientName:@"ANDROID"
                                        videoId:videoId
                                     completion:^(NSString *androidURL, BOOL androidMuxed, NSError *androidError) {
                if (androidURL.length) {
                    if (completion) completion(androidURL, androidMuxed, nil);
                    return;
                }
                NSError *last = androidError ?: iosError ?: vrError;
                NSString *msg = [NSString stringWithFormat:@"All playback sources failed.\nLast error: %@",
                                 last.localizedDescription ?: @"unknown"];
                if (completion) completion(nil, NO, [weakSelf errorWithCode:2 message:msg]);
            }];
        }];
    }];
}

- (void)fetchStreamURLWithContext:(NSDictionary *)context
                         clientName:(NSString *)clientName
                            videoId:(NSString *)videoId
                         completion:(void (^)(NSString *streamURL, BOOL muxedStream, NSError *error))completion {
    if (!videoId.length) {
        if (completion) completion(nil, NO, [self errorWithCode:1 message:@"Missing video id"]);
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
            if (completion) completion(nil, NO, error);
            return;
        }
        NSDictionary *playability = [json objectForKey:@"playabilityStatus"];
        NSString *status = [playability objectForKey:@"status"];
        if (![status isEqualToString:@"OK"]) {
            NSString *reason = [playability objectForKey:@"reason"];
            if (!reason.length) reason = @"Playback unavailable";
            NSLog(@"LTYouTubeClient: player status=%@ reason=%@ for videoId=%@ client=%@", status, reason, videoId, clientName);
            LTLog(@"PLAYER status=%@ reason=%@ videoId=%@ client=%@", status, reason, videoId, clientName);
            if (completion) completion(nil, NO, [self errorWithCode:2 message:reason]);
            return;
        }
        NSDictionary *sd = [json objectForKey:@"streamingData"];
        NSDictionary *best = nil;
        id stored = [[NSUserDefaults standardUserDefaults] objectForKey:@"LTStreamingQuality"];
        NSInteger quality = stored ? [stored integerValue] : 2;
        if (quality < 0) quality = 0;
        if (quality > 2) quality = 2;
        NSArray *orders = @[
            @[@139, @140, @141],
            @[@140, @141, @139],
            @[@141, @140, @139],
        ];
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
            NSString *mime = [best objectForKey:@"mimeType"] ?: @"";
            BOOL muxed = ([mime rangeOfString:@"video/"].location != NSNotFound);
            BOOL hasN = ([url rangeOfString:@"&n="].location != NSNotFound || [url rangeOfString:@"?n="].location != NSNotFound);
            LTLog(@"STREAM client=%@ itag=%d muxed=%d videoId=%@ hasN=%d fullurl=%@", clientName, [[best objectForKey:@"itag"] intValue], muxed, videoId, hasN, url);
            if (completion) completion(url, muxed, nil);
        } else {
            NSLog(@"LTYouTubeClient: no playable stream found for videoId=%@", videoId);
            if (completion) completion(nil, NO, [self errorWithCode:3 message:@"No playable stream found"]);
        }
    }];
}

#pragma mark - Images

- (void)loadImageWithURL:(NSString *)urlString
              completion:(void (^)(UIImage *image))completion {
    if (!urlString.length) {
        if (completion) completion(nil);
        return;
    }
    UIImage *cached = [self.imageCache objectForKey:urlString];
    if (cached) {
        if (completion) completion(cached);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                           cachePolicy:NSURLRequestReturnCacheDataElseLoad
                                                       timeoutInterval:30.0];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError || !data.length) {
            if (completion) completion(nil);
            return;
        }
        UIImage *image = [UIImage imageWithData:data];
        if (image) [self.imageCache setObject:image forKey:urlString];
        if (completion) completion(image);
    }];
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
    id url = LTPath(item, @"thumbnail", @"musicThumbnailRenderer", @"thumbnail", @"thumbnails", @0, @"url", nil);
    if ([url isKindOfClass:[NSString class]] && [(NSString *)url length]) return url;
    return nil;
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
