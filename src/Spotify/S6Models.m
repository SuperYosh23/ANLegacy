#import "S6Models.h"
#import "S6Common.h"

NSString *S6URIType(NSString *uri)
{
    NSArray *parts = [uri componentsSeparatedByString:@":"];
    return parts.count >= 3 ? [parts objectAtIndex:(parts.count - 2)] : nil;
}

NSString *S6URIId(NSString *uri)
{
    NSArray *parts = [uri componentsSeparatedByString:@":"];
    return parts.count >= 3 ? parts.lastObject : nil;
}

NSString *S6FormatDurationMs(NSInteger ms)
{
    NSInteger total = MAX(0, (ms + 500) / 1000);
    NSInteger h = total / 3600, m = (total / 60) % 60, s = total % 60;
    if (h) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

NSString *S6PlainText(NSString *html)
{
    if (!html.length) return html;
    if ([html rangeOfString:@"<"].location == NSNotFound && [html rangeOfString:@"&"].location == NSNotFound) return html;
    static NSRegularExpression *tags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]*>" options:0 error:NULL]; });
    NSMutableString *s = [[tags stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0, html.length) withTemplate:@""] mutableCopy];
    NSDictionary *entities = @{ @"&quot;": @"\"", @"&#x27;": @"'", @"&#39;": @"'", @"&apos;": @"'", @"&lt;": @"<", @"&gt;": @">",
                                @"&nbsp;": @" ", @"&#x2F;": @"/" };
    for (NSString *e in entities) [s replaceOccurrencesOfString:e withString:[entities objectForKey:e] options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange(0, s.length)];
    return s;
}

#pragma mark - GraphQL helpers

// "2013-05-20T00:00:00Z" or {year, month, day} -> "2013-05-20" (or just the year)
static NSString *S6GQLDate(id date)
{
    NSDictionary *d = S6Dict(date);
    NSString *iso = S6Str([d objectForKey:@"isoString"]);
    if (iso.length >= 10) return [iso substringToIndex:10];
    if (iso.length >= 4) return iso;
    NSInteger y = S6Int([d objectForKey:@"year"]);
    if (!y) return nil;
    NSInteger m = S6Int([d objectForKey:@"month"]), day = S6Int([d objectForKey:@"day"]);
    if (m && day) return [NSString stringWithFormat:@"%04ld-%02ld-%02ld", (long)y, (long)m, (long)day];
    return [NSString stringWithFormat:@"%04ld", (long)y];
}

static NSInteger S6GQLDuration(NSDictionary *d)
{
    NSDictionary *duration = S6Dict([d objectForKey:@"duration"]) ?: S6Dict([d objectForKey:@"trackDuration"]);
    return S6Int([duration objectForKey:@"totalMilliseconds"]);
}

static BOOL S6GQLPlayable(NSDictionary *d)
{
    NSDictionary *p = S6Dict([d objectForKey:@"playability"]);
    return [p objectForKey:@"playable"] ? S6Bool([p objectForKey:@"playable"]) : YES;
}

static NSString *S6GQLURI(NSDictionary *d) { return S6Str([d objectForKey:@"uri"]) ?: S6Str([d objectForKey:@"_uri"]); }

#pragma mark - Images

@implementation S6Image

+ (NSString *)urlIn:(id)images forSize:(CGFloat)pixels
{
    NSArray *list = S6Arr(images);
    NSString *best = nil, *biggest = nil;
    NSInteger bestWidth = NSIntegerMax, biggestWidth = -1;
    for (id item in list) {
        NSDictionary *d = S6Dict(item);
        NSString *url = S6Str([d objectForKey:@"url"]);
        if (!url.length) continue;
        NSInteger w = S6Int([d objectForKey:@"width"]);
        if (w == 0) w = 640;   // (some images say nothing about their size)
        if (w >= pixels && w < bestWidth) { best = url; bestWidth = w; }
        if (w > biggestWidth) { biggest = url; biggestWidth = w; }
    }
    return best ?: biggest;
}

@end

#pragma mark - Artist

@implementation S6Artist

+ (instancetype)artistFromJSON:(NSDictionary *)json
{
    NSDictionary *j = S6Dict(json);
    if (!j) return nil;
    S6Artist *a = [[S6Artist alloc] init];
    a.artistId = S6Str([j objectForKey:@"id"]);
    a.uri = S6Str([j objectForKey:@"uri"]) ?: (a.artistId ? [@"spotify:artist:" stringByAppendingString:a.artistId] : nil);
    a.name = S6Str([j objectForKey:@"name"]) ?: @"";
    a.images = S6Arr([j objectForKey:@"images"]);
    a.followers = S6Int([S6Dict([j objectForKey:@"followers"]) objectForKey:@"total"]);
    a.genres = S6Arr([j objectForKey:@"genres"]);
    return a;
}

+ (instancetype)artistFromGraphQL:(NSDictionary *)data
{
    NSDictionary *d = S6Dict(data);
    NSString *uri = S6GQLURI(d);
    if (!uri.length) return nil;
    S6Artist *a = [[S6Artist alloc] init];
    a.uri = uri;
    a.artistId = S6Str([d objectForKey:@"id"]) ?: S6URIId(uri);
    a.name = S6Str([S6Dict([d objectForKey:@"profile"]) objectForKey:@"name"]) ?: S6Str([d objectForKey:@"name"]) ?: @"";
    a.images = S6Arr([S6Dict([S6Dict([d objectForKey:@"visuals"]) objectForKey:@"avatarImage"]) objectForKey:@"sources"]);
    NSDictionary *stats = S6Dict([d objectForKey:@"stats"]);
    a.followers = S6Int([stats objectForKey:@"followers"]);
    a.monthlyListeners = S6Int([stats objectForKey:@"monthlyListeners"]);
    a.saved = S6Bool([d objectForKey:@"saved"]);
    return a;
}

- (NSString *)imageURLForSize:(CGFloat)pixels { return [S6Image urlIn:self.images forSize:pixels]; }

@end

static NSArray *S6ArtistsFrom(id list)
{
    NSMutableArray *out = [NSMutableArray array];
    for (id a in S6Arr(list)) {
        S6Artist *artist = [S6Artist artistFromJSON:a];
        if (artist) [out addObject:artist];
    }
    return out;
}

static NSArray *S6GQLArtists(id artists)
{
    NSMutableArray *out = [NSMutableArray array];
    for (id item in S6Arr([S6Dict(artists) objectForKey:@"items"])) {
        S6Artist *a = [S6Artist artistFromGraphQL:item];
        if (a) [out addObject:a];
    }
    return out;
}

static NSString *S6Names(NSArray *artists)
{
    NSMutableArray *names = [NSMutableArray array];
    for (S6Artist *a in artists) if (a.name.length) [names addObject:a.name];
    return [names componentsJoinedByString:@", "];
}

#pragma mark - Album

@implementation S6Album

+ (instancetype)albumFromJSON:(NSDictionary *)json
{
    NSDictionary *j = S6Dict(json);
    if (!j) return nil;
    S6Album *a = [[S6Album alloc] init];
    a.albumId = S6Str([j objectForKey:@"id"]);
    a.uri = S6Str([j objectForKey:@"uri"]) ?: (a.albumId ? [@"spotify:album:" stringByAppendingString:a.albumId] : nil);
    a.name = S6Str([j objectForKey:@"name"]) ?: @"";
    a.artists = S6ArtistsFrom([j objectForKey:@"artists"]);
    a.images = S6Arr([j objectForKey:@"images"]);
    a.albumType = S6Str([j objectForKey:@"album_type"]) ?: S6Str([j objectForKey:@"type"]);
    a.releaseDate = S6Str([j objectForKey:@"release_date"]);
    a.totalTracks = S6Int([j objectForKey:@"total_tracks"]);
    a.label = S6Str([j objectForKey:@"label"]);
    NSDictionary *tracks = S6Dict([j objectForKey:@"tracks"]);
    if (tracks) {
        NSMutableArray *list = [NSMutableArray array];
        for (id t in S6Arr([tracks objectForKey:@"items"])) {
            S6Track *track = [S6Track trackFromJSON:t album:a];
            if (track) [list addObject:track];
        }
        a.tracks = list;
    }
    return a;
}

+ (instancetype)albumFromGraphQL:(NSDictionary *)data
{
    NSDictionary *d = S6Dict(data);
    NSString *uri = S6GQLURI(d);
    if (!uri.length) return nil;
    S6Album *a = [[S6Album alloc] init];
    a.uri = uri;
    a.albumId = S6Str([d objectForKey:@"id"]) ?: S6URIId(uri);
    a.name = S6Str([d objectForKey:@"name"]) ?: @"";
    a.artists = S6GQLArtists([d objectForKey:@"artists"]);
    a.images = S6Arr([S6Dict([d objectForKey:@"coverArt"]) objectForKey:@"sources"]);
    a.albumType = [S6Str([d objectForKey:@"type"]) lowercaseString];
    a.releaseDate = S6GQLDate([d objectForKey:@"date"]);
    a.label = S6Str([d objectForKey:@"label"]);
    a.totalTracks = S6Int([S6Dict([d objectForKey:@"tracksV2"]) objectForKey:@"totalCount"]) ?: S6Int([S6Dict([d objectForKey:@"tracks"]) objectForKey:@"totalCount"]);
    a.saved = S6Bool([d objectForKey:@"saved"]);
    return a;
}

- (NSString *)imageURLForSize:(CGFloat)pixels { return [S6Image urlIn:self.images forSize:pixels]; }
- (NSString *)artistNames { return S6Names(self.artists); }
- (NSString *)year { return self.releaseDate.length >= 4 ? [self.releaseDate substringToIndex:4] : @""; }

@end

#pragma mark - Track

@implementation S6Track

+ (instancetype)trackFromJSON:(NSDictionary *)json { return [self trackFromJSON:json album:nil]; }

+ (instancetype)trackFromJSON:(NSDictionary *)json album:(S6Album *)album
{
    NSDictionary *j = S6Dict(json);
    if (!j) return nil;
    S6Track *t = [[S6Track alloc] init];
    t.trackId = S6Str([j objectForKey:@"id"]);
    NSString *type = S6Str([j objectForKey:@"type"]) ?: @"track";
    t.isEpisode = [type isEqualToString:@"episode"];
    t.uri = S6Str([j objectForKey:@"uri"]) ?: (t.trackId ? [NSString stringWithFormat:@"spotify:%@:%@", type, t.trackId] : nil);
    t.name = S6Str([j objectForKey:@"name"]) ?: @"";
    t.artists = S6ArtistsFrom([j objectForKey:@"artists"]);
    t.album = album ?: [S6Album albumFromJSON:[j objectForKey:@"album"]];
    if (t.isEpisode) {
        // an episode: the show stands where the album would be (a show's own episode list leaves the show out)
        NSDictionary *show = S6Dict([j objectForKey:@"show"]);
        S6Album *a = [[S6Album alloc] init];
        a.name = S6Str([show objectForKey:@"name"]) ?: album.name ?: @"";
        a.uri = S6Str([show objectForKey:@"uri"]) ?: album.uri;
        a.images = S6Arr([j objectForKey:@"images"]) ?: S6Arr([show objectForKey:@"images"]) ?: album.images;
        t.album = a;
        if (!t.artists.count) {
            S6Artist *publisher = [[S6Artist alloc] init];
            publisher.name = S6Str([show objectForKey:@"publisher"]) ?: a.name;
            t.artists = @[ publisher ];
        }
    }
    t.durationMs = S6Int([j objectForKey:@"duration_ms"]);
    t.explicitContent = S6Bool([j objectForKey:@"explicit"]);
    t.playable = [j objectForKey:@"is_playable"] ? S6Bool([j objectForKey:@"is_playable"]) : YES;
    if (S6Bool([j objectForKey:@"is_local"])) t.playable = NO;
    t.trackNumber = S6Int([j objectForKey:@"track_number"]);
    t.discNumber = S6Int([j objectForKey:@"disc_number"]);
    return t;
}

+ (instancetype)trackFromGraphQL:(NSDictionary *)data album:(S6Album *)album
{
    NSDictionary *d = S6Dict(data);
    NSString *uri = S6GQLURI(d);
    if (!uri.length) return nil;
    NSString *type = S6Str([d objectForKey:@"__typename"]);
    S6Track *t = [[S6Track alloc] init];
    t.uri = uri;
    t.isEpisode = [type isEqualToString:@"Episode"] || [S6URIType(uri) isEqualToString:@"episode"];
    t.trackId = S6Str([d objectForKey:@"id"]) ?: S6URIId(uri);
    t.name = S6Str([d objectForKey:@"name"]) ?: @"";
    t.durationMs = S6GQLDuration(d);
    t.playable = S6GQLPlayable(d);
    if ([type isEqualToString:@"LocalTrack"] || [S6URIType(uri) isEqualToString:@"local"]) t.playable = NO;
    t.explicitContent = [S6Str([S6Dict([d objectForKey:@"contentRating"]) objectForKey:@"label"]) isEqualToString:@"EXPLICIT"];
    t.trackNumber = S6Int([d objectForKey:@"trackNumber"]);
    t.discNumber = S6Int([d objectForKey:@"discNumber"]);
    t.playcount = [S6Str([d objectForKey:@"playcount"]) longLongValue];
    if (t.isEpisode) {
        // an episode: its show stands where the album would be, the publisher where the artists would
        NSDictionary *show = S6Dict([S6Dict([d objectForKey:@"podcastV2"]) objectForKey:@"data"]);
        S6Album *a = [[S6Album alloc] init];
        a.name = S6Str([show objectForKey:@"name"]) ?: album.name ?: @"";
        a.uri = S6Str([show objectForKey:@"uri"]) ?: album.uri;
        a.images = S6Arr([S6Dict([d objectForKey:@"coverArt"]) objectForKey:@"sources"]) ?: S6Arr([S6Dict([show objectForKey:@"coverArt"]) objectForKey:@"sources"]) ?: album.images;
        t.album = a;
        S6Artist *publisher = [[S6Artist alloc] init];
        publisher.name = S6Str([S6Dict([show objectForKey:@"publisher"]) objectForKey:@"name"]) ?: a.name;
        t.artists = @[ publisher ];
        t.releaseDate = S6GQLDate([d objectForKey:@"releaseDate"]);
        return t;
    }
    t.artists = S6GQLArtists([d objectForKey:@"artists"]);
    NSDictionary *albumData = S6Dict([d objectForKey:@"albumOfTrack"]);
    t.album = albumData ? [S6Album albumFromGraphQL:albumData] : album;
    if (t.album != album && album && !t.album.images.count) t.album.images = album.images;
    return t;
}

- (NSString *)artistNames { return S6Names(self.artists); }
- (NSString *)imageURLForSize:(CGFloat)pixels { return [self.album imageURLForSize:pixels]; }

- (NSDictionary *)toJSON
{
    NSMutableArray *artists = [NSMutableArray array];
    for (S6Artist *a in self.artists) [artists addObject:@{ @"id": a.artistId ?: @"", @"name": a.name ?: @"", @"uri": a.uri ?: @"" }];
    NSMutableDictionary *album = [NSMutableDictionary dictionary];
    if (self.album) {
        [album setObject:self.album.albumId ?: @"" forKey:@"id"];
        [album setObject:self.album.name ?: @"" forKey:@"name"];
        [album setObject:self.album.uri ?: @"" forKey:@"uri"];
        [album setObject:self.album.images ?: [NSArray array] forKey:@"images"];
    }
    return @{ @"id": self.trackId ?: @"", @"uri": self.uri ?: @"", @"name": self.name ?: @"", @"type": self.isEpisode ? @"episode" : @"track",
              @"artists": artists, @"album": album, @"duration_ms": @(self.durationMs), @"explicit": @(self.explicitContent),
              @"is_playable": @(self.playable) };
}

@end

#pragma mark - Playlist

@implementation S6Playlist

+ (instancetype)playlistFromJSON:(NSDictionary *)json
{
    NSDictionary *j = S6Dict(json);
    if (!j) return nil;
    S6Playlist *p = [[S6Playlist alloc] init];
    p.playlistId = S6Str([j objectForKey:@"id"]);
    p.uri = S6Str([j objectForKey:@"uri"]) ?: (p.playlistId ? [@"spotify:playlist:" stringByAppendingString:p.playlistId] : nil);
    p.name = S6Str([j objectForKey:@"name"]) ?: @"";
    p.descriptionText = S6Str([j objectForKey:@"description"]);
    NSDictionary *owner = S6Dict([j objectForKey:@"owner"]);
    p.ownerName = S6Str([owner objectForKey:@"display_name"]) ?: S6Str([owner objectForKey:@"id"]);
    p.ownerId = S6Str([owner objectForKey:@"id"]);
    p.images = S6Arr([j objectForKey:@"images"]);
    NSDictionary *tracks = S6Dict([j objectForKey:@"tracks"]) ?: S6Dict([j objectForKey:@"items"]);
    p.totalTracks = S6Int([tracks objectForKey:@"total"]);
    p.followers = S6Int([S6Dict([j objectForKey:@"followers"]) objectForKey:@"total"]);
    p.collaborative = S6Bool([j objectForKey:@"collaborative"]);
    p.snapshotId = S6Str([j objectForKey:@"snapshot_id"]);
    return p;
}

+ (instancetype)playlistFromGraphQL:(NSDictionary *)data
{
    NSDictionary *d = S6Dict(data);
    NSString *uri = S6GQLURI(d);
    if (!uri.length) return nil;
    S6Playlist *p = [[S6Playlist alloc] init];
    p.uri = uri;
    p.playlistId = S6Str([d objectForKey:@"id"]) ?: S6URIId(uri);
    p.name = S6Str([d objectForKey:@"name"]) ?: @"";
    p.descriptionText = S6PlainText(S6Str([d objectForKey:@"description"]));
    NSDictionary *owner = S6Dict([S6Dict([d objectForKey:@"ownerV2"]) objectForKey:@"data"]);
    p.ownerName = S6Str([owner objectForKey:@"name"]) ?: S6Str([owner objectForKey:@"username"]);
    p.ownerId = S6Str([owner objectForKey:@"username"]) ?: S6Str([owner objectForKey:@"id"]);
    NSArray *_imgItems = S6Arr([S6Dict([d objectForKey:@"images"]) objectForKey:@"items"]);
    NSDictionary *_img0 = _imgItems.count ? S6Dict([_imgItems objectAtIndex:0]) : nil;
    p.images = S6Arr([_img0 objectForKey:@"sources"]);
    p.totalTracks = S6Int([S6Dict([d objectForKey:@"content"]) objectForKey:@"totalCount"]);
    p.followers = S6Int([d objectForKey:@"followers"]);
    p.editable = S6Bool([S6Dict([d objectForKey:@"currentUserCapabilities"]) objectForKey:@"canEditItems"]);
    p.saved = S6Bool([d objectForKey:@"following"]);
    return p;
}

- (NSString *)imageURLForSize:(CGFloat)pixels { return [S6Image urlIn:self.images forSize:pixels]; }

@end

#pragma mark - Show

@implementation S6Show

+ (instancetype)showFromJSON:(NSDictionary *)json
{
    NSDictionary *j = S6Dict(json);
    if (!j) return nil;
    S6Show *s = [[S6Show alloc] init];
    s.showId = S6Str([j objectForKey:@"id"]);
    s.uri = S6Str([j objectForKey:@"uri"]);
    s.name = S6Str([j objectForKey:@"name"]) ?: @"";
    s.publisher = S6Str([j objectForKey:@"publisher"]);
    s.descriptionText = S6Str([j objectForKey:@"description"]);
    s.images = S6Arr([j objectForKey:@"images"]);
    return s;
}

+ (instancetype)showFromGraphQL:(NSDictionary *)data
{
    NSDictionary *d = S6Dict(data);
    NSString *uri = S6GQLURI(d);
    if (!uri.length) return nil;
    S6Show *s = [[S6Show alloc] init];
    s.uri = uri;
    s.showId = S6Str([d objectForKey:@"id"]) ?: S6URIId(uri);
    s.name = S6Str([d objectForKey:@"name"]) ?: @"";
    s.publisher = S6Str([S6Dict([d objectForKey:@"publisher"]) objectForKey:@"name"]);
    s.descriptionText = S6PlainText(S6Str([d objectForKey:@"description"]));
    s.images = S6Arr([S6Dict([d objectForKey:@"coverArt"]) objectForKey:@"sources"]);
    s.saved = S6Bool([d objectForKey:@"saved"]);
    return s;
}

- (NSString *)imageURLForSize:(CGFloat)pixels { return [S6Image urlIn:self.images forSize:pixels]; }

@end

#pragma mark - Any entity

id S6EntityFromGraphQL(NSDictionary *node)
{
    NSDictionary *d = S6Dict(node);
    for (int depth = 0; d && depth < 5; depth++) {
        NSString *type = S6Str([d objectForKey:@"__typename"]);
        if ([type isEqualToString:@"Track"] || [type isEqualToString:@"Episode"]) return [S6Track trackFromGraphQL:d album:nil];
        if ([type isEqualToString:@"Album"]) return [S6Album albumFromGraphQL:d];
        if ([type isEqualToString:@"Artist"]) return [S6Artist artistFromGraphQL:d];
        if ([type isEqualToString:@"Playlist"]) return [S6Playlist playlistFromGraphQL:d];
        if ([type isEqualToString:@"Podcast"]) return [S6Show showFromGraphQL:d];
        // wrappers: {data: …}, {item: …}, {content: …}, {itemV2: …}, {entity: …}
        NSDictionary *inner = S6Dict([d objectForKey:@"data"]) ?: S6Dict([d objectForKey:@"item"]) ?: S6Dict([d objectForKey:@"content"]) ?: S6Dict([d objectForKey:@"itemV2"]) ?: S6Dict([d objectForKey:@"entity"]);
        if (!inner || inner == d) return nil;
        d = inner;
    }
    return nil;
}
