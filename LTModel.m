#import "LTModel.h"

@implementation LTTrack

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self.title.length) dict[@"title"] = self.title;
    if (self.artist.length) dict[@"artist"] = self.artist;
    if (self.album.length) dict[@"album"] = self.album;
    if (self.videoId.length) dict[@"videoId"] = self.videoId;
    if (self.thumbnailURL.length) dict[@"thumbnail"] = self.thumbnailURL;
    if (self.duration > 0) dict[@"duration"] = @(self.duration);
    return dict;
}

+ (instancetype)trackWithDictionary:(NSDictionary *)dict {
    LTTrack *track = [[LTTrack alloc] init];
    track.title = dict[@"title"];
    track.artist = dict[@"artist"];
    track.album = dict[@"album"];
    track.videoId = dict[@"videoId"];
    track.thumbnailURL = dict[@"thumbnail"];
    track.duration = [dict[@"duration"] doubleValue];
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
    return @{
        @"identifier": self.identifier ?: @"",
        @"name": self.name ?: @"",
        @"tracks": trackDicts,
    };
}

+ (instancetype)playlistWithDictionary:(NSDictionary *)dict {
    LTLocalPlaylist *playlist = [[LTLocalPlaylist alloc] init];
    playlist.identifier = dict[@"identifier"];
    playlist.name = dict[@"name"];
    [playlist.tracks removeAllObjects];
    NSArray *trackDicts = dict[@"tracks"];
    if ([trackDicts isKindOfClass:[NSArray class]]) {
        for (NSDictionary *td in trackDicts) {
            LTTrack *track = [LTTrack trackWithDictionary:td];
            if (track.videoId.length) [playlist.tracks addObject:track];
        }
    }
    return playlist;
}

@end
