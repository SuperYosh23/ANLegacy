#import "LTModel.h"

@implementation LTTrack

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.title.length) [dict setObject:self.title forKey:@"title"];
    if (self.artist.length) [dict setObject:self.artist forKey:@"artist"];
    if (self.album.length) [dict setObject:self.album forKey:@"album"];
    if (self.videoId.length) [dict setObject:self.videoId forKey:@"videoId"];
    if (self.thumbnailURL.length) [dict setObject:self.thumbnailURL forKey:@"thumbnail"];
    if (self.duration > 0) [dict setObject:@(self.duration) forKey:@"duration"];
    return dict;
}

+ (instancetype)trackWithDictionary:(NSDictionary *)dict {
    LTTrack *track = [[LTTrack alloc] init];
    track.title = [dict objectForKey:@"title"];
    track.artist = [dict objectForKey:@"artist"];
    track.album = [dict objectForKey:@"album"];
    track.videoId = [dict objectForKey:@"videoId"];
    // Desktop sync payloads use "thumbnail", our own format uses "thumbnailURL".
    track.thumbnailURL = [dict objectForKey:@"thumbnailURL"] ?: [dict objectForKey:@"thumbnail"];
    track.duration = [[dict objectForKey:@"duration"] doubleValue];
    return track;
}

@end

@implementation LTBrowseItem
@end

@implementation LTLocalPlaylist

- (id)init {
    self = [super init];
    if (self) {
        _tracks = [NSMutableArray array];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *trackDicts = [NSMutableArray array];
    for (LTTrack *track in self.tracks) {
        [trackDicts addObject:[track dictionaryRepresentation]];
    }
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
        @"identifier": self.identifier ?: @"",
        @"name": self.name ?: @"",
        @"tracks": trackDicts,
    }];
    if (self.coverPath.length) [dict setObject:self.coverPath forKey:@"coverPath"];
    return dict;
}

+ (instancetype)playlistWithDictionary:(NSDictionary *)dict {
    LTLocalPlaylist *playlist = [[LTLocalPlaylist alloc] init];
    playlist.identifier = [dict objectForKey:@"identifier"];
    playlist.name = [dict objectForKey:@"name"];
    playlist.coverPath = [dict objectForKey:@"coverPath"];
    [playlist.tracks removeAllObjects];
    NSArray *trackDicts = [dict objectForKey:@"tracks"];
    if ([trackDicts isKindOfClass:[NSArray class]]) {
        for (NSDictionary *td in trackDicts) {
            LTTrack *track = [LTTrack trackWithDictionary:td];
            if (track.videoId.length) [playlist.tracks addObject:track];
        }
    }
    return playlist;
}

@end

@implementation LTStationSeed
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.type) [d setObject:self.type forKey:@"type"];
    if (self.videoId) [d setObject:self.videoId forKey:@"videoId"];
    if (self.artist) [d setObject:self.artist forKey:@"artist"];
    if (self.album) [d setObject:self.album forKey:@"album"];
    if (self.title) [d setObject:self.title forKey:@"title"];
    if (self.thumbnailURL) [d setObject:self.thumbnailURL forKey:@"thumbnailURL"];
    if (self.browseId) [d setObject:self.browseId forKey:@"browseId"];
    return d;
}
+ (instancetype)seedWithDictionary:(NSDictionary *)dict {
    LTStationSeed *s = [[LTStationSeed alloc] init];
    s.type = [dict objectForKey:@"type"];
    s.videoId = [dict objectForKey:@"videoId"];
    s.artist = [dict objectForKey:@"artist"];
    s.album = [dict objectForKey:@"album"];
    s.title = [dict objectForKey:@"title"];
    s.thumbnailURL = [dict objectForKey:@"thumbnailURL"];
    s.browseId = [dict objectForKey:@"browseId"];
    return s;
}
@end

@implementation LTStation
- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.identifier) [d setObject:self.identifier forKey:@"identifier"];
    if (self.name) [d setObject:self.name forKey:@"name"];
    if (self.coverPath) [d setObject:self.coverPath forKey:@"coverPath"];
    NSMutableArray *arr = [NSMutableArray array];
    for (id s in self.seeds) {
        if ([s respondsToSelector:@selector(dictionaryRepresentation)]) [arr addObject:[s dictionaryRepresentation]];
    }
    if (arr.count) [d setObject:arr forKey:@"seeds"];
    return d;
}
+ (instancetype)stationWithDictionary:(NSDictionary *)dict {
    LTStation *st = [[LTStation alloc] init];
    st.identifier = [dict objectForKey:@"identifier"];
    st.name = [dict objectForKey:@"name"];
    st.coverPath = [dict objectForKey:@"coverPath"];
    NSMutableArray *arr = [NSMutableArray array];
    NSArray *seeds = [dict objectForKey:@"seeds"];
    if ([seeds isKindOfClass:[NSArray class]]) {
        for (id s in seeds) {
            if ([s isKindOfClass:[NSDictionary class]]) {
                LTStationSeed *seed = [LTStationSeed seedWithDictionary:s];
                if (seed) [arr addObject:seed];
            }
        }
    }
    st.seeds = arr;
    return st;
}
@end
