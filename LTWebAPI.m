#import "LTWebAPI.h"
#import "S6JSON.h"
#import "LTArtworkBackground.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTPlaylistStore.h"
#import "LTLog.h"
#import "LTTheme.h"
#import "LTHaptics.h"
#import "LTTransitionSettings.h"
#import "LTOneHandedMode.h"
#import "LTAppIcon.h"
#import "LTLyricsSettings.h"
#import "LTSleepTimer.h"

// The port the embedded server listens on. Must match LTWebShellViewController.
static const NSInteger kLTWebAudioPort = 3614;

@implementation LTWebAPI

#pragma mark - Shapes

// The shape the web app's toSong() expects.
+ (NSDictionary *)dictionaryForTrack:(LTTrack *)track {
    NSMutableArray *artists = [NSMutableArray array];
    if (track.artist.length) {
        [artists addObject:@{@"name": track.artist, @"id": @""}];
    }
    NSMutableArray *thumbnails = [NSMutableArray array];
    NSString *thumb = track.thumbnailURL;
    if (thumb.length) [thumbnails addObject:@{@"url": thumb}];

    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [out setObject:track.videoId ?: @"" forKey:@"videoId"];
    [out setObject:track.title ?: @"" forKey:@"title"];
    [out setObject:artists forKey:@"artists"];
    [out setObject:track.artist ?: @"" forKey:@"channelTitle"];
    [out setObject:@"" forKey:@"channelId"];
    [out setObject:thumbnails forKey:@"thumbnails"];
    [out setObject:@(track.duration) forKey:@"duration_seconds"];
    [out setObject:@{@"name": track.album ?: @"", @"id": @""} forKey:@"album"];
    return out;
}

+ (NSDictionary *)dictionaryForBrowseItem:(LTBrowseItem *)item {
    NSMutableArray *artists = [NSMutableArray array];
    if (item.subtitle.length) [artists addObject:@{@"name": item.subtitle, @"id": @""}];
    NSMutableArray *thumbnails = [NSMutableArray array];
    if (item.thumbnailURL.length) [thumbnails addObject:@{@"url": item.thumbnailURL}];

    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [out setObject:@"album" forKey:@"type"];
    [out setObject:item.browseId ?: @"" forKey:@"browseId"];
    [out setObject:item.browseId ?: @"" forKey:@"playlistId"];
    [out setObject:item.title ?: @"" forKey:@"title"];
    [out setObject:item.subtitle ?: @"" forKey:@"artist"];
    [out setObject:item.subtitle ?: @"" forKey:@"channelTitle"];
    [out setObject:@"" forKey:@"channelId"];
    [out setObject:thumbnails forKey:@"thumbnails"];
    [out setObject:@(0) forKey:@"itemCount"];
    [out setObject:@(0) forKey:@"trackCount"];
    [out setObject:@"" forKey:@"year"];
    return out;
}

#pragma mark - Dispatch

- (NSData *)handleMethod:(NSString *)method
                    path:(NSString *)path
                   query:(NSString *)query
                    body:(NSData *)body
                  status:(NSInteger *)status {
    NSInteger code = 200;
    NSDictionary *payload = nil;
    NSArray *items = nil;

    NSString *tail = [path hasPrefix:@"/api/"] ? [path substringFromIndex:5] : path;
    NSArray *parts = [tail componentsSeparatedByString:@"/"];
    NSString *head = [parts count] ? [parts objectAtIndex:0] : nil;
    NSString *rest = @"";
    NSArray *segments = [tail componentsSeparatedByString:@"/"];
    if (segments.count > 1) {
        rest = [[segments subarrayWithRange:NSMakeRange(1, segments.count - 1)] componentsJoinedByString:@"/"];
    }

    NSDictionary *params = [self parseQuery:query];

    if ([head isEqualToString:@"search"]) {
        NSString *kind = [segments count] > 1 ? [segments objectAtIndex:1] : @"songs";
        NSString *q = [params objectForKey:@"q"] ?: @"";
        NSInteger limit = [[params objectForKey:@"limit"] integerValue];
        if (limit <= 0) limit = 20;
        items = [self search:q kind:kind limit:limit];
        payload = @{@"results": items ?: [NSArray array]};
    } else if ([head isEqualToString:@"artist"]) {
        // Artist search, as opposed to /api/artist/<id> which is one artist's
        // page. The two share a prefix, so the browse form is distinguished by
        // having an id after it.
        if (rest.length) {
            payload = [self artistForBrowseId:rest];
        } else {
            NSString *q = [params objectForKey:@"q"] ?: @"";
            NSInteger limit = [[params objectForKey:@"limit"] integerValue];
            if (limit <= 0) limit = 10;
            payload = @{@"results": [self search:q kind:@"artists" limit:limit] ?: [NSArray array]};
        }
    } else if ([head isEqualToString:@"album"]) {
        if (rest.length) {
            payload = [self albumForBrowseId:rest];
        } else {
            NSString *q = [params objectForKey:@"q"] ?: @"";
            NSInteger limit = [[params objectForKey:@"limit"] integerValue];
            if (limit <= 0) limit = 10;
            payload = @{@"results": [self search:q kind:@"albums" limit:limit] ?: [NSArray array]};
        }
    } else if ([head isEqualToString:@"artist"]) {
        payload = [self artistForBrowseId:rest];
    } else if ([head isEqualToString:@"playlist"]) {
        // A local playlist wins over a YouTube one with the same id: the
        // phone's own playlists are what the web app's playlist list holds.
        NSDictionary *local = [self localPlaylistWithIdentifier:rest];
        payload = local ?: [self playlistForBrowseId:rest];
    } else if ([head isEqualToString:@"song"]) {
        payload = [self songForVideoId:rest];
    } else if ([head isEqualToString:@"lyrics"]) {
        if ([rest hasPrefix:@"check/"]) {
            NSString *videoId = [rest substringFromIndex:6];
            payload = @{@"available": @([self hasLyricsForVideoId:videoId])};
        } else {
            payload = [self lyricsForVideoId:rest];
            if (![payload isKindOfClass:[NSDictionary class]] || [payload objectForKey:@"error"]) code = 404;
        }
    } else if ([head isEqualToString:@"audio"]) {
        payload = [self audioForVideoId:rest];
        if (![payload isKindOfClass:[NSDictionary class]]) code = 404;
    } else if ([head isEqualToString:@"albumart"]) {
        // Best-effort: the desktop app asks Deezer for cover art by title and
        // artist. The phone already has artwork for most tracks it knows, but
        // it has no equivalent service, so this answers with nothing rather
        // than failing the request.
        payload = @{@"url": [NSNull null]};
    } else if ([head isEqualToString:@"recommendations"]) {
        // Not implemented on the phone. An empty list lets the UI render
        // without the section rather than erroring out.
        payload = @{@"tracks": [NSArray array]};
    } else if ([head isEqualToString:@"download"]) {
        payload = @{@"status": @"unsupported", @"message": @"Downloading is only available in the native app."};
    } else if ([head isEqualToString:@"log"]) {
        // The web page posts uncaught JavaScript errors here. A blank page on
        // the phone is otherwise invisible: no crash, no console, nothing.
        NSDictionary *report = [NSDictionary dictionary];
        if (body.length) {
            id parsed = [S6JSON objectWithData:body error:NULL];
            if ([parsed isKindOfClass:[NSDictionary class]]) report = parsed;
        }
        // Newlines are flattened: the log is line-based, and a stack that spans
        // lines puts the error message somewhere other than where the reader is
        // looking.
        NSString *message = [[report objectForKey:@"message"] ?: @"" stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        NSString *extra = [[report objectForKey:@"extra"] ?: @"" stringByReplacingOccurrencesOfString:@"\n" withString:@" | "];
        LTLog(@"WEBJS %@: %@", [report objectForKey:@"kind"] ?: @"error", message);
        if (extra.length) LTLog(@"WEBJS   at: %@", extra);
        payload = @{@"ok": @YES};
    } else if ([head isEqualToString:@"settings"]) {
        if ([method isEqualToString:@"POST"]) {
            payload = [self applySettingFromBody:body];
        } else {
            payload = @{@"settings": [self currentSettings]};
        }
    } else if ([head isEqualToString:@"local"]) {
        if ([rest isEqualToString:@"playlists"]) {
            payload = @{@"playlists": [self localPlaylists]};
        } else if ([rest isEqualToString:@"library"]) {
            payload = @{@"tracks": [self localLibrary]};
        } else if ([rest isEqualToString:@"recents"]) {
            payload = @{@"tracks": [self localRecents]};
        } else {
            code = 404;
            payload = @{@"error": @"unknown local route"};
        }
    } else {
        code = 404;
        payload = @{@"error": @"unknown route"};
    }

    if (status) *status = code;

    if (!payload) {
        payload = @{@"error": @"failed"};
        if (status) *status = 500;
    }
    NSData *json = [S6JSON dataWithObject:payload error:NULL];
    return json ?: [NSData data];
}

#pragma mark - Routes

- (NSArray *)search:(NSString *)query kind:(NSString *)kind limit:(NSInteger)limit {
    if (!query.length) return [NSArray array];

    // The web app asks for "songs" and "albums"; the iOS client uses the same
    // type names.
    __block NSArray *results = [NSArray array];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[LTYouTubeClient sharedClient] searchWithQuery:query type:kind completion:^(NSArray *items, NSError *error) {
        NSMutableArray *mapped = [NSMutableArray array];
        for (id item in items) {
            if ([item isKindOfClass:[LTTrack class]]) {
                [mapped addObject:[LTWebAPI dictionaryForTrack:(LTTrack *)item]];
            } else if ([item isKindOfClass:[LTBrowseItem class]]) {
                [mapped addObject:[LTWebAPI dictionaryForBrowseItem:(LTBrowseItem *)item]];
            }
            if ((NSInteger)mapped.count >= limit) break;
        }
        results = mapped;
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)));
    return results;
}

- (NSDictionary *)albumForBrowseId:(NSString *)browseId {
    if (!browseId.length) return @{@"error": @"missing browse id"};
    __block NSDictionary *out = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[LTYouTubeClient sharedClient] browseAlbum:browseId completion:^(NSDictionary *info, NSArray *tracks, NSError *error) {
        if (error) {
            out = @{@"error": error.localizedDescription ?: @"failed"};
        } else {
            NSMutableArray *trackDicts = [NSMutableArray array];
            for (LTTrack *track in tracks) {
                NSMutableDictionary *d = [[LTWebAPI dictionaryForTrack:track] mutableCopy];
                [d setObject:@{@"name": [info objectForKey:@"title"] ?: track.album ?: @"", @"id": browseId} forKey:@"album"];
                [trackDicts addObject:d];
            }
            NSMutableArray *thumbnails = [NSMutableArray array];
            NSString *thumb = [info objectForKey:@"thumbnail"];
            if (thumb.length) [thumbnails addObject:@{@"url": thumb}];
            out = @{
                @"title": [info objectForKey:@"title"] ?: @"",
                @"artists": @[@{@"name": [info objectForKey:@"subtitle"] ?: @"", @"id": @""}],
                @"year": [info objectForKey:@"year"] ?: @"",
                @"thumbnails": thumbnails,
                @"tracks": trackDicts,
            };
        }
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)));
    return out ?: @{@"error": @"timeout"};
}

- (NSDictionary *)artistForBrowseId:(NSString *)browseId {
    if (!browseId.length) return @{@"error": @"missing browse id"};
    __block NSDictionary *out = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[LTYouTubeClient sharedClient] browseArtist:browseId
                                         completion:^(NSDictionary *info, NSArray *topSongs, NSArray *allSongs, NSArray *albums, NSError *error) {
        if (error) {
            out = @{@"error": error.localizedDescription ?: @"failed"};
        } else {
            NSMutableArray *trackDicts = [NSMutableArray array];
            for (LTTrack *track in allSongs.count ? allSongs : topSongs) {
                [trackDicts addObject:[LTWebAPI dictionaryForTrack:track]];
            }
            NSMutableArray *albumDicts = [NSMutableArray array];
            for (LTBrowseItem *album in albums) {
                [albumDicts addObject:[LTWebAPI dictionaryForBrowseItem:album]];
            }
            NSMutableArray *thumbnails = [NSMutableArray array];
            NSString *thumb = [info objectForKey:@"thumbnail"];
            if (thumb.length) [thumbnails addObject:@{@"url": thumb}];
            out = @{
                @"title": [info objectForKey:@"title"] ?: @"",
                @"artists": @[@{@"name": [info objectForKey:@"title"] ?: @"", @"id": browseId}],
                @"thumbnails": thumbnails,
                @"tracks": trackDicts,
                @"albums": albumDicts,
            };
        }
        dispatch_semaphore_signal(done);
    } avatarURL:nil];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)));
    return out ?: @{@"error": @"timeout"};
}

- (NSDictionary *)playlistForBrowseId:(NSString *)browseId {
    if (!browseId.length) return @{@"error": @"missing playlist id"};
    __block NSDictionary *out = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[LTYouTubeClient sharedClient] browsePlaylist:browseId completion:^(NSDictionary *info, NSArray *tracks, NSError *error) {
        if (error) {
            out = @{@"error": error.localizedDescription ?: @"failed"};
        } else {
            NSMutableArray *trackDicts = [NSMutableArray array];
            for (LTTrack *track in tracks) {
                [trackDicts addObject:[LTWebAPI dictionaryForTrack:track]];
            }
            NSMutableArray *thumbnails = [NSMutableArray array];
            NSString *thumb = [info objectForKey:@"thumbnail"];
            if (thumb.length) [thumbnails addObject:@{@"url": thumb}];
            out = @{
                @"title": [info objectForKey:@"title"] ?: @"",
                @"owner": @{@"name": [info objectForKey:@"subtitle"] ?: @""},
                @"thumbnails": thumbnails,
                @"trackCount": @(tracks.count),
                @"tracks": trackDicts,
            };
        }
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)));
    return out ?: @{@"error": @"timeout"};
}

- (NSDictionary *)songForVideoId:(NSString *)videoId {
    if (!videoId.length) return @{@"error": @"missing video id"};
    __block NSDictionary *out = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[LTYouTubeClient sharedClient] fetchVideoGeneralInfoForVideoId:videoId completion:^(NSDictionary *info, NSError *error) {
        if (error) {
            out = @{@"error": error.localizedDescription ?: @"failed"};
        } else {
            NSMutableArray *thumbnails = [NSMutableArray array];
            out = @{
                @"videoDetails": @{
                    @"videoId": videoId,
                    @"title": [info objectForKey:@"title"] ?: @"",
                    @"author": [info objectForKey:@"uploader"] ?: @"",
                    @"channelId": [info objectForKey:@"channelId"] ?: @"",
                    @"lengthSeconds": @((int)([[info objectForKey:@"durationSeconds"] doubleValue])),
                    @"shortDescription": @"",
                    @"thumbnail": @{@"thumbnails": thumbnails},
                },
                @"microformat": [NSDictionary dictionary],
            };
        }
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)));
    return out ?: @{@"error": @"timeout"};
}

- (BOOL)hasLyricsForVideoId:(NSString *)videoId {
    __block BOOL available = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[LTYouTubeClient sharedClient] fetchTimedLyricsForVideoId:videoId completion:^(NSDictionary *result, NSError *error) {
        available = (result != nil && [result count] > 0);
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    return available;
}

- (NSDictionary *)lyricsForVideoId:(NSString *)videoId {
    __block NSDictionary *out = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[LTYouTubeClient sharedClient] fetchTimedLyricsForVideoId:videoId completion:^(NSDictionary *result, NSError *error) {
        out = result;
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
    if (![out isKindOfClass:[NSDictionary class]]) return @{@"error": @"no lyrics available"};
    return out;
}

// The web app's own track shape.
//
// The phone's track shape and the web app's differ: the web app wants a flat
// `thumbnail` string and `artists` with an `artistId` key, where the phone
// has a `thumbnails` array and `artists` with `id`. The web app's own toSong()
// maps one into the other, so the phone's API is given the shape that mapper
// expects to be handed.
+ (NSDictionary *)webSongDictionaryForTrack:(LTTrack *)track {
    NSMutableArray *artists = [NSMutableArray array];
    if (track.artist.length) {
        [artists addObject:@{@"name": track.artist, @"artistId": @""}];
    }
    NSString *thumb = track.thumbnailURL;
    return @{
        @"videoId": track.videoId ?: @"",
        @"title": track.title ?: @"",
        @"artists": artists,
        @"channelTitle": track.artist ?: @"",
        @"channelId": @"",
        @"thumbnail": thumb ?: @"",
        @"duration": @(track.duration),
        @"album": track.album ?: @"",
        @"albumId": @"",
    };
}

- (NSDictionary *)audioForVideoId:(NSString *)videoId {
    if (!videoId.length) return @{@"error": @"missing video id"};

    // A downloaded track is served from the phone, so playback works with no
    // network at all and does not depend on a stream URL staying valid.
    NSString *localPath = [[LTPlaylistStore sharedStore] localFilePathForVideoId:videoId];
    if (localPath.length && [[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
        return @{
            @"url": [NSString stringWithFormat:@"http://127.0.0.1:%ld/audio/%@", (long)kLTWebAudioPort, videoId],
            @"title": @"",
            @"duration": @(0),
            @"local": @YES,
        };
    }

    __block NSDictionary *out = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[LTYouTubeClient sharedClient] streamURLForVideo:videoId completion:^(NSString *streamURL, BOOL muxed, NSInteger bitrate, NSError *error) {
        if (streamURL.length) {
            out = @{@"url": streamURL, @"title": @"", @"duration": @(0)};
        } else {
            out = @{@"error": error.localizedDescription ?: @"No audio stream found"};
        }
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)));
    return out ?: @{@"error": @"timeout"};
}

// The bytes of a downloaded track, for the /audio/<videoId> route.
- (NSData *)fileDataForPath:(NSString *)path {
    return [LTWebAPI audioFileDataForVideoId:path];
}

+ (NSData *)audioFileDataForVideoId:(NSString *)videoId {
    if (!videoId.length) return nil;
    NSString *path = [[LTPlaylistStore sharedStore] localFilePathForVideoId:videoId];
    if (!path.length) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    return [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
}

#pragma mark - Settings

// The native app's settings, so the web app can show the same list of
// preferences and change the same ones.
- (NSDictionary *)currentSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];

    [out setObject:@([defaults boolForKey:@"LTKeepAwake"]) forKey:@"keepAwake"];
    [out setObject:@([defaults boolForKey:@"LTShowKbpsCounter"]) forKey:@"showKbpsCounter"];
    [out setObject:@([LTArtworkBackground enabled]) forKey:@"albumArtBackground"];
    [out setObject:@([LTTransitionSettings animationsEnabled]) forKey:@"animationsEnabled"];
    [out setObject:@([LTTransitionSettings speedMultiplier]) forKey:@"transitionSpeed"];
    [out setObject:@([defaults boolForKey:@"LTiPodModeEnabled"]) forKey:@"iPodModeEnabled"];
    [out setObject:@([LTOneHandedMode mode]) forKey:@"oneHandedMode"];
    [out setObject:@([LTOneHandedMode isSupported]) forKey:@"oneHandedSupported"];
    [out setObject:@([defaults floatForKey:@"LTHomeTileSize"]) forKey:@"recentsTileSize"];
    [out setObject:@([LTHaptics strength]) forKey:@"hapticStrength"];
    [out setObject:[LTHaptics currentStrengthLabel] forKey:@"hapticStrengthLabel"];
    [out setObject:@(LTLyricsOffset()) forKey:@"lyricsOffset"];
    [out setObject:[LTAppIcon currentIconName] ?: @"" forKey:@"appIcon"];
    [out setObject:[LTAppIcon currentIconLabel] ?: @"" forKey:@"appIconLabel"];
    [out setObject:@([LTAppIcon isPickerSupported]) forKey:@"appIconPickerSupported"];
    [out setObject:@([LTTheme currentTheme]) forKey:@"theme"];
    [out setObject:[LTTheme nameForTheme:[LTTheme currentTheme]] forKey:@"themeName"];

    [out setObject:@([[LTSleepTimer shared] isActive]) forKey:@"sleepTimerActive"];
    [out setObject:@([[LTSleepTimer shared] remainingMinutes]) forKey:@"sleepTimerMinutes"];

    [out setObject:@([[LTPlaylistStore sharedStore] offlineFileCount]) forKey:@"offlineDownloads"];
    [out setObject:@([[LTPlaylistStore sharedStore] pendingDownloadCount]) forKey:@"pendingDownloads"];
    [out setObject:@([[LTPlaylistStore sharedStore] playlists].count) forKey:@"playlists"];

    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    [out setObject:version ?: @"" forKey:@"version"];
    return out;
}

// Applies one setting. Only the simple ones are settable from the web app; the
// ones that need a native screen (the icon picker, the sleep timer sheet) are
// left to the native app.
- (NSDictionary *)applySettingFromBody:(NSData *)body {
    NSDictionary *request = [NSDictionary dictionary];
    if (body.length) {
        id parsed = [S6JSON objectWithData:body error:NULL];
        if ([parsed isKindOfClass:[NSDictionary class]]) request = parsed;
    }
    NSString *key = [request objectForKey:@"key"];
    id value = [request objectForKey:@"value"];
    if (!key.length) return @{@"error": @"missing key"};

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([key isEqualToString:@"keepAwake"]) {
        [defaults setBool:[value boolValue] forKey:@"LTKeepAwake"];
    } else if ([key isEqualToString:@"showKbpsCounter"]) {
        [defaults setBool:[value boolValue] forKey:@"LTShowKbpsCounter"];
    } else if ([key isEqualToString:@"albumArtBackground"]) {
        [LTArtworkBackground setEnabled:[value boolValue]];
    } else if ([key isEqualToString:@"animationsEnabled"]) {
        [LTTransitionSettings setAnimationsEnabled:[value boolValue]];
    } else if ([key isEqualToString:@"transitionSpeed"]) {
        [LTTransitionSettings setSpeedMultiplier:[value doubleValue]];
    } else if ([key isEqualToString:@"iPodModeEnabled"]) {
        [defaults setBool:[value boolValue] forKey:@"LTiPodModeEnabled"];
    } else if ([key isEqualToString:@"oneHandedMode"]) {
        [LTOneHandedMode setMode:(LTOneHandedCorner)[value integerValue]];
    } else if ([key isEqualToString:@"hapticStrength"]) {
        [LTHaptics setStrength:(LTHapticStrength)[value integerValue]];
    } else if ([key isEqualToString:@"lyricsOffset"]) {
        LTSetLyricsOffset([value doubleValue]);
    } else if ([key isEqualToString:@"theme"]) {
        // Setting the theme posts LTThemeDidChangeNotification, and the app
        // delegate rebuilds the root - which is how the web app hands control
        // back to the native one. Without this the modern themes are a one-way
        // door: the native picker is not reachable from inside the web app.
        [LTTheme setCurrentTheme:(LTThemeStyle)[value integerValue]];
    } else {
        return @{@"error": [NSString stringWithFormat:@"%@ cannot be changed here", key]};
    }
    [defaults synchronize];

    // The sleep timer and the icon picker need native screens.
    if ([key isEqualToString:@"sleepTimerMinutes"]) {
        NSInteger minutes = [value integerValue];
        if (minutes > 0) [[LTSleepTimer shared] startWithMinutes:minutes];
        else [[LTSleepTimer shared] cancel];
    }

    return @{@"ok": @YES, @"settings": [self currentSettings]};
}

#pragma mark - Local content

- (NSDictionary *)localPlaylistWithIdentifier:(NSString *)identifier {
    if (!identifier.length) return nil;
    for (LTLocalPlaylist *playlist in [[LTPlaylistStore sharedStore] playlists]) {
        if (![playlist.identifier isEqualToString:identifier]) continue;
        NSMutableArray *tracks = [NSMutableArray array];
        for (LTTrack *track in playlist.tracks) {
            [tracks addObject:[LTWebAPI dictionaryForTrack:track]];
        }
        NSMutableArray *thumbnails = [NSMutableArray array];
        if (playlist.coverPath.length) {
            [thumbnails addObject:@{@"url": [NSString stringWithFormat:@"file://%@", playlist.coverPath]}];
        }
        return @{
            @"title": playlist.name ?: @"",
            @"owner": @{@"name": @""},
            @"thumbnails": thumbnails,
            @"trackCount": @(tracks.count),
            @"tracks": tracks,
        };
    }
    return nil;
}

- (NSArray *)localPlaylists {
    NSMutableArray *out = [NSMutableArray array];
    NSString *stamp = [[NSDate date] description];
    for (LTLocalPlaylist *playlist in [[LTPlaylistStore sharedStore] playlists]) {
        NSMutableArray *songs = [NSMutableArray array];
        for (LTTrack *track in playlist.tracks) {
            [songs addObject:[LTWebAPI webSongDictionaryForTrack:track]];
        }
        // The web app's own playlist shape, so its existing code can use this
        // without needing to know where it came from.
        [out addObject:@{
            @"id": playlist.identifier ?: @"",
            @"name": playlist.name ?: @"",
            @"description": @"",
            @"songs": songs,
            @"createdAt": stamp,
            @"updatedAt": stamp,
        }];
    }
    return out;
}

- (NSArray *)localLibrary {
    NSMutableArray *out = [NSMutableArray array];
    for (LTTrack *track in [[LTPlaylistStore sharedStore] libraryTracks]) {
        [out addObject:[LTWebAPI dictionaryForTrack:track]];
    }
    return out;
}

- (NSArray *)localRecents {
    NSMutableArray *out = [NSMutableArray array];
    for (LTTrack *track in [[LTPlaylistStore sharedStore] recentTracks]) {
        [out addObject:[LTWebAPI dictionaryForTrack:track]];
    }
    return out;
}

#pragma mark - Helpers

- (NSDictionary *)parseQuery:(NSString *)query {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (!query.length) return out;
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSRange eq = [pair rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *key = [pair substringToIndex:eq.location];
        NSString *value = [pair substringFromIndex:eq.location + 1];
        // The server already percent-decodes the whole query string; values can
        // still carry a '+' meaning a space.
        value = [value stringByReplacingOccurrencesOfString:@"+" withString:@" "];
        [out setObject:value forKey:key];
    }
    return out;
}

@end
