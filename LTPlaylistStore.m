#import "LTPlaylistStore.h"
#import "LTYouTubeClient.h"
#import "LTLog.h"

#define kLTListenedSongIDsKey @"LTListenedSongIDs2"

NSString *const LTPlaylistsDidChangeNotification = @"LTPlaylistsDidChangeNotification";
NSString *const LTPlaylistTrackDidChangeNotification = @"LTPlaylistTrackDidChangeNotification";
NSString *const LTPlaylistDownloadProgressNotification = @"LTPlaylistDownloadProgressNotification";
NSString *const LTRecentsDidChangeNotification = @"LTRecentsDidChangeNotification";

@interface LTPlaylistStore () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSMutableArray *playlists;
@property (nonatomic, strong) NSMutableArray *downloadQueue;
@property (nonatomic, strong) NSURLConnection *downloadConnection;
@property (nonatomic, strong) NSMutableData *downloadData;
@property (nonatomic, copy) NSString *downloadingVideoId;
@property (nonatomic, strong) LTTrack *downloadingTrack;
@property (nonatomic, assign) BOOL downloadingMuxed;
@property (nonatomic, assign) NSInteger downloadHTTPStatus;
@property (nonatomic, assign) NSInteger downloadTotal;
@property (nonatomic, assign) NSInteger downloadIndex;
@property (nonatomic, copy) void (^downloadCompletion)(void);
@property (nonatomic, assign) BOOL downloading;
@property (nonatomic, strong) NSMutableArray *libraryTracks;
@end

@implementation LTStatsEntry
@end

@implementation LTPlaylistStore

+ (instancetype)sharedStore {
    static LTPlaylistStore *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[LTPlaylistStore alloc] init];
    });
    return shared;
}

- (id)init {
    self = [super init];
    if (self) {
        _playlists = [NSMutableArray array];
        _downloadQueue = [NSMutableArray array];
        _libraryTracks = [NSMutableArray array];
        [self ensureDirectories];
        [self loadPlaylists];
        [self loadLibrary];
    }
    return self;
}

- (NSString *)baseDirectory {
    return @"/var/mobile/Documents/LegacyMusic";
}

- (NSString *)audioDirectory {
    return [self.baseDirectory stringByAppendingPathComponent:@"audio"];
}

- (NSString *)artDirectory {
    return [self.baseDirectory stringByAppendingPathComponent:@"art"];
}

- (void)ensureDirectories {
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[self baseDirectory]
                              withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) LTLog(@"STORE mkdir base error: %@", error);
    error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[self audioDirectory]
                              withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) LTLog(@"STORE mkdir audio error: %@", error);
    error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[self artDirectory]
                              withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) LTLog(@"STORE mkdir art error: %@", error);
}

- (NSString *)playlistsFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"playlists.plist"];
}

- (void)loadPlaylists {
    NSArray *plist = [NSArray arrayWithContentsOfFile:[self playlistsFilePath]];
    if (![plist isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *dict in plist) {
        LTLocalPlaylist *playlist = [LTLocalPlaylist playlistWithDictionary:dict];
        if (playlist.identifier.length) [_playlists addObject:playlist];
    }
    LTLog(@"STORE loaded %d playlists", (int)self.playlists.count);
}

- (void)savePlaylists {
    NSMutableArray *plist = [NSMutableArray array];
    for (LTLocalPlaylist *playlist in self.playlists) {
        [plist addObject:[playlist dictionaryRepresentation]];
    }
    BOOL ok = [plist writeToFile:[self playlistsFilePath] atomically:YES];
    if (!ok) LTLog(@"STORE save failed");
}

- (void)postPlaylistsChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:self];
}

#pragma mark - Library

- (NSString *)libraryFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"library.plist"];
}

- (void)loadLibrary {
    NSArray *plist = [NSArray arrayWithContentsOfFile:[self libraryFilePath]];
    if (![plist isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *dict in plist) {
        LTTrack *track = [LTTrack trackWithDictionary:dict];
        if (track.videoId.length) [_libraryTracks addObject:track];
    }
    LTLog(@"STORE loaded %d library tracks", (int)self.libraryTracks.count);
}

- (void)saveLibrary {
    NSMutableArray *plist = [NSMutableArray array];
    for (LTTrack *track in self.libraryTracks) {
        [plist addObject:[track dictionaryRepresentation]];
    }
    [plist writeToFile:[self libraryFilePath] atomically:YES];
}

- (void)addTrackToLibrary:(LTTrack *)track {
    if (!track.videoId.length) return;
    for (LTTrack *existing in self.libraryTracks) {
        if ([existing.videoId isEqualToString:track.videoId]) {
            if (!existing.title.length && track.title.length) existing.title = track.title;
            if (!existing.artist.length && track.artist.length) existing.artist = track.artist;
            if (!existing.album.length && track.album.length) existing.album = track.album;
            if (!existing.thumbnailURL.length && track.thumbnailURL.length) existing.thumbnailURL = track.thumbnailURL;
            if (existing.duration <= 0 && track.duration > 0) existing.duration = track.duration;
            [self saveLibrary];
            return;
        }
    }
    LTTrack *copy = [[LTTrack alloc] init];
    copy.title = track.title;
    copy.artist = track.artist;
    copy.album = track.album;
    copy.videoId = track.videoId;
    copy.thumbnailURL = track.thumbnailURL;
    copy.duration = track.duration;
    [_libraryTracks addObject:copy];
    [self saveLibrary];
    [self postPlaylistsChanged];
    LTLog(@"STORE added %@ to library", track.videoId);
}

- (NSArray *)downloadedTracks {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (LTLocalPlaylist *playlist in self.playlists) {
        for (LTTrack *track in playlist.tracks) {
            if (!track.videoId.length) continue;
            if ([seen containsObject:track.videoId]) continue;
            if (![self existingLocalFilePathForVideoId:track.videoId]) continue;
            [seen addObject:track.videoId];
            [result addObject:track];
        }
    }
    for (LTTrack *track in self.libraryTracks) {
        if (!track.videoId.length) continue;
        if ([seen containsObject:track.videoId]) continue;
        if (![self existingLocalFilePathForVideoId:track.videoId]) continue;
        [seen addObject:track.videoId];
        [result addObject:track];
    }
    return result;
}

- (void)removeDownloadsForTracks:(NSArray *)tracks {
    NSMutableArray *changedVideoIds = [NSMutableArray array];
    for (LTTrack *track in tracks) {
        NSString *path = [self existingLocalFilePathForVideoId:track.videoId];
        if (path.length) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            [changedVideoIds addObject:track.videoId];
        }
    }
    if (changedVideoIds.count) {
        for (NSInteger i = (NSInteger)self.libraryTracks.count - 1; i >= 0; i--) {
            LTTrack *libTrack = [self.libraryTracks objectAtIndex:(NSUInteger)i];
            if ([changedVideoIds containsObject:libTrack.videoId]) {
                [_libraryTracks removeObjectAtIndex:(NSUInteger)i];
            }
        }
        [self saveLibrary];
    }
    for (NSString *videoId in changedVideoIds) {
        [self postTrackChanged:videoId];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:self];
}

- (void)postTrackChanged:(NSString *)videoId {
    if (videoId.length) {
        [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistTrackDidChangeNotification
                                                            object:self
                                                          userInfo:@{@"videoId": videoId}];
    }
}

#pragma mark - Playlist CRUD

- (LTLocalPlaylist *)createPlaylistWithName:(NSString *)name {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return nil;
    LTLocalPlaylist *playlist = [[LTLocalPlaylist alloc] init];
    playlist.identifier = [NSString stringWithFormat:@"local-%lld", (long long)[[NSDate date] timeIntervalSince1970]];
    playlist.name = trimmed;
    [_playlists addObject:playlist];
    [self savePlaylists];
    [self postPlaylistsChanged];
    LTLog(@"STORE created playlist %@ (%@)", playlist.name, playlist.identifier);
    return playlist;
}

- (void)deletePlaylist:(LTLocalPlaylist *)playlist {
    [_playlists removeObject:playlist];
    [self savePlaylists];
    [self postPlaylistsChanged];
    LTLog(@"STORE deleted playlist %@", playlist.name);
}

- (void)renamePlaylist:(LTLocalPlaylist *)playlist name:(NSString *)name {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return;
    playlist.name = trimmed;
    [self savePlaylists];
    [self postPlaylistsChanged];
}

- (void)setCoverImage:(UIImage *)image forPlaylist:(LTLocalPlaylist *)playlist {
    if (!playlist.identifier.length) return;
    // Remove old cover if exists
    if (playlist.coverPath.length) {
        [[NSFileManager defaultManager] removeItemAtPath:playlist.coverPath error:nil];
        playlist.coverPath = nil;
    }
    if (image) {
        NSString *path = [[self artDirectory] stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"cover-%@.jpg", playlist.identifier]];
        NSData *data = UIImageJPEGRepresentation(image, 0.85);
        if (data) {
            [data writeToFile:path atomically:YES];
            playlist.coverPath = path;
            LTLog(@"STORE saved cover for playlist %@ at %@", playlist.name, path);
        }
    }
    [self savePlaylists];
    [self postPlaylistsChanged];
}

- (void)addTrack:(LTTrack *)track toPlaylist:(LTLocalPlaylist *)playlist {
    if (!track.videoId.length) return;
    for (LTTrack *existing in playlist.tracks) {
        if ([existing.videoId isEqualToString:track.videoId]) return;
    }
    [playlist.tracks addObject:track];
    [self savePlaylists];
    [self postPlaylistsChanged];
    LTLog(@"STORE added track %@ to %@", track.videoId, playlist.name);
}

- (void)removeTrackAtIndex:(NSInteger)index fromPlaylist:(LTLocalPlaylist *)playlist {
    if (index < 0 || index >= (NSInteger)playlist.tracks.count) return;
    [playlist.tracks removeObjectAtIndex:(NSUInteger)index];
    [self savePlaylists];
    [self postPlaylistsChanged];
}

#pragma mark - Offline files

- (NSString *)localFilePathForVideoId:(NSString *)videoId {
    if (!videoId.length) return nil;
    return [[self audioDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", videoId]];
}

- (NSString *)existingLocalFilePathForVideoId:(NSString *)videoId {
    NSString *m4a = [self localFilePathForVideoId:videoId];
    if (m4a.length && [[NSFileManager defaultManager] fileExistsAtPath:m4a]) return m4a;
    if (!videoId.length) return nil;
    NSString *mp4 = [[self audioDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", videoId]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:mp4]) return mp4;
    return nil;
}

- (BOOL)isTrackDownloaded:(LTTrack *)track {
    NSString *path = [self existingLocalFilePathForVideoId:track.videoId];
    return path.length > 0;
}

- (BOOL)isTrackDownloading:(LTTrack *)track {
    if (![self isDownloading]) return NO;
    if (!track.videoId.length) return NO;
    return [self.downloadingVideoId isEqualToString:track.videoId];
}

- (BOOL)isDownloading {
    return _downloading;
}

#pragma mark - Recently played

- (NSString *)recentsFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"recents.plist"];
}

- (NSArray *)recentTracks {
    NSArray *plist = [NSArray arrayWithContentsOfFile:[self recentsFilePath]];
    NSMutableArray *tracks = [NSMutableArray array];
    if ([plist isKindOfClass:[NSArray class]]) {
        for (NSDictionary *dict in plist) {
            LTTrack *track = [LTTrack trackWithDictionary:dict];
            if (track.videoId.length) [tracks addObject:track];
        }
    }
    return tracks;
}

- (void)recordRecentTrack:(LTTrack *)track {
    if (!track.videoId.length) return;
    NSMutableArray *ids = [NSMutableArray arrayWithArray:[self listenedSongIDs]];
    if (![ids containsObject:track.videoId]) {
        [ids addObject:track.videoId];
        [[NSUserDefaults standardUserDefaults] setObject:ids forKey:kLTListenedSongIDsKey];
    }
    NSMutableArray *plist = [NSMutableArray array];
    [plist addObject:[track dictionaryRepresentation]];
    NSInteger count = 1;
    for (LTTrack *old in [self recentTracks]) {
        if ([old.videoId isEqualToString:track.videoId]) continue;
        [plist addObject:[old dictionaryRepresentation]];
        count += 1;
        if (count >= 20) break;
    }
    [plist writeToFile:[self recentsFilePath] atomically:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTRecentsDidChangeNotification object:self];
}

- (NSArray *)listenedSongIDs {
    NSArray *ids = [[NSUserDefaults standardUserDefaults] arrayForKey:kLTListenedSongIDsKey];
    if (ids) return ids;
    // First run: seed from every song the store knows about (recents, playlists,
    // library) so the counter reflects all history, not just the 4-file recents cap.
    NSMutableArray *seed = [NSMutableArray array];
    void (^addVideoId)(NSString *) = ^(NSString *videoId) {
        if (videoId.length && ![seed containsObject:videoId]) {
            [seed addObject:videoId];
        }
    };
    for (LTTrack *track in [self recentTracks]) addVideoId(track.videoId);
    for (LTLocalPlaylist *playlist in self.playlists) {
        for (LTTrack *track in playlist.tracks) addVideoId(track.videoId);
    }
    for (LTTrack *track in self.libraryTracks) addVideoId(track.videoId);
    [[NSUserDefaults standardUserDefaults] setObject:seed forKey:kLTListenedSongIDsKey];
    return seed;
}

- (NSInteger)listenedSongsCount {
    return (NSInteger)[[self listenedSongIDs] count];
}

#pragma mark - Search history

- (NSArray *)searchHistory {
    NSArray *terms = [[NSUserDefaults standardUserDefaults] arrayForKey:@"LTSearchHistory"];
    if (![terms isKindOfClass:[NSArray class]]) return @[];
    return terms;
}

- (void)recordSearchTerm:(NSString *)term {
    if (!term.length) return;
    NSMutableArray *terms = [NSMutableArray arrayWithArray:[self searchHistory]];
    [terms removeObject:term];
    [terms insertObject:term atIndex:0];
    if (terms.count > 20) {
        [terms removeObjectsInRange:NSMakeRange(20, terms.count - 20)];
    }
    [[NSUserDefaults standardUserDefaults] setObject:terms forKey:@"LTSearchHistory"];
}

- (void)clearSearchHistory {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LTSearchHistory"];
}

#pragma mark - Listening stats

- (NSString *)statsFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"stats.plist"];
}

- (NSMutableDictionary *)statsFileDict {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:[self statsFilePath]];
    if ([dict isKindOfClass:[NSDictionary class]]) {
        return [NSMutableDictionary dictionaryWithDictionary:dict];
    }
    return [NSMutableDictionary dictionary];
}

- (void)writeStatsFileDict:(NSDictionary *)dict {
    if (![dict writeToFile:[self statsFilePath] atomically:YES]) {
        LTLog(@"STATS write failed");
    }
}

- (NSMutableDictionary *)statsEntryForVideoId:(NSString *)videoId inDict:(NSMutableDictionary *)dict {
    if (!videoId.length) return nil;
    NSMutableDictionary *tracks = [dict objectForKey:@"tracks"];
    if (![tracks isKindOfClass:[NSMutableDictionary class]]) {
        tracks = [NSMutableDictionary dictionary];
        [dict setObject:tracks forKey:@"tracks"];
    }
    NSMutableDictionary *entry = [tracks objectForKey:videoId];
    if (![entry isKindOfClass:[NSMutableDictionary class]]) {
        entry = [NSMutableDictionary dictionary];
        [tracks setObject:entry forKey:videoId];
    }
    return entry;
}

- (void)recordTrackPlay:(LTTrack *)track {
    if (!track.videoId.length) return;
    NSMutableDictionary *dict = [self statsFileDict];
    NSMutableDictionary *entry = [self statsEntryForVideoId:track.videoId inDict:dict];
    NSInteger plays = [[entry objectForKey:@"plays"] integerValue];
    [entry setObject:@(plays + 1) forKey:@"plays"];
    [entry setObject:track.title ?: @"" forKey:@"title"];
    if (track.artist.length) [entry setObject:track.artist forKey:@"artist"];
    if (track.album.length) [entry setObject:track.album forKey:@"album"];
    if (track.thumbnailURL.length) [entry setObject:track.thumbnailURL forKey:@"thumbnailURL"];
    [self writeStatsFileDict:dict];
}

- (void)recordListenedSeconds:(NSTimeInterval)seconds forTrack:(LTTrack *)track {
    if (!track.videoId.length || seconds <= 0) return;
    NSMutableDictionary *dict = [self statsFileDict];
    NSMutableDictionary *entry = [self statsEntryForVideoId:track.videoId inDict:dict];
    NSTimeInterval current = [[entry objectForKey:@"seconds"] doubleValue];
    [entry setObject:@(current + seconds) forKey:@"seconds"];
    [entry setObject:track.title ?: @"" forKey:@"title"];
    if (track.artist.length) [entry setObject:track.artist forKey:@"artist"];
    if (track.album.length) [entry setObject:track.album forKey:@"album"];
    if (track.thumbnailURL.length) [entry setObject:track.thumbnailURL forKey:@"thumbnailURL"];
    [self writeStatsFileDict:dict];
}

- (NSArray *)statsEntries {
    NSMutableDictionary *dict = [self statsFileDict];
    NSDictionary *tracks = [dict objectForKey:@"tracks"];
    if (![tracks isKindOfClass:[NSDictionary class]]) return @[];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *videoId in tracks) {
        NSDictionary *data = [tracks objectForKey:videoId];
        LTStatsEntry *entry = [[LTStatsEntry alloc] init];
        entry.videoId = videoId;
        entry.title = [data objectForKey:@"title"];
        entry.artist = [data objectForKey:@"artist"];
        entry.thumbnailURL = [data objectForKey:@"thumbnailURL"];
        entry.plays = [[data objectForKey:@"plays"] integerValue];
        entry.seconds = [[data objectForKey:@"seconds"] doubleValue];
        [entries addObject:entry];
    }
    return entries;
}

- (NSArray *)mostPlayedTracks {
    NSArray *entries = [self statsEntries];
    return [entries sortedArrayUsingComparator:^NSComparisonResult(LTStatsEntry *a, LTStatsEntry *b) {
        if (a.plays != b.plays) return (a.plays > b.plays) ? NSOrderedAscending : NSOrderedDescending;
        if (a.seconds != b.seconds) return (a.seconds > b.seconds) ? NSOrderedAscending : NSOrderedDescending;
        return [a.title compare:b.title];
    }];
}

- (NSArray *)topArtists {
    NSMutableDictionary *byArtist = [NSMutableDictionary dictionary];
    for (LTStatsEntry *entry in [self statsEntries]) {
        NSString *artist = entry.artist.length ? entry.artist : @"Unknown Artist";
        NSMutableDictionary *agg = [byArtist objectForKey:artist];
        if (!agg) {
            agg = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                   @(0), @"plays", @(0.0), @"seconds", nil];
            [byArtist setObject:agg forKey:artist];
        }
        [agg setObject:@([[agg objectForKey:@"plays"] integerValue] + entry.plays) forKey:@"plays"];
        [agg setObject:@([[agg objectForKey:@"seconds"] doubleValue] + entry.seconds) forKey:@"seconds"];
    }
    NSArray *sorted = [byArtist keysSortedByValueUsingComparator:^NSComparisonResult(id a, id b) {
        NSTimeInterval sa = [[a objectForKey:@"seconds"] doubleValue];
        NSTimeInterval sb = [[b objectForKey:@"seconds"] doubleValue];
        if (sa != sb) return (sa > sb) ? NSOrderedAscending : NSOrderedDescending;
        NSInteger pa = [[a objectForKey:@"plays"] integerValue];
        NSInteger pb = [[b objectForKey:@"plays"] integerValue];
        if (pa != pb) return (pa > pb) ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *artist in sorted) {
        NSDictionary *agg = [byArtist objectForKey:artist];
        NSMutableDictionary *row = [NSMutableDictionary dictionary];
        [row setObject:artist forKey:@"name"];
        [row setObject:[agg objectForKey:@"plays"] forKey:@"plays"];
        [row setObject:[agg objectForKey:@"seconds"] forKey:@"seconds"];
        [result addObject:row];
    }
    return result;
}

- (NSTimeInterval)totalListeningTime {
    NSTimeInterval total = 0;
    for (LTStatsEntry *entry in [self statsEntries]) total += entry.seconds;
    return total;
}

- (NSInteger)totalPlayCount {
    NSInteger total = 0;
    for (LTStatsEntry *entry in [self statsEntries]) total += entry.plays;
    return total;
}

- (NSInteger)offlineFileCount {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self audioDirectory] error:nil];
    if (![files isKindOfClass:[NSArray class]]) return 0;
    NSInteger count = 0;
    for (NSString *name in files) {
        if ([name hasSuffix:@".m4a"] || [name hasSuffix:@".mp4"]) count += 1;
    }
    return count;
}

#pragma mark - Download for offline

- (void)downloadTracks:(NSArray *)tracks completion:(void (^)(void))completion {
    if (self.downloading) return;
    if (!tracks.count) {
        if (completion) completion();
        return;
    }
    self.downloadCompletion = completion;
    self.downloadTotal = (NSInteger)tracks.count;
    self.downloadIndex = 0;
    [self.downloadQueue removeAllObjects];
    [self.downloadQueue addObjectsFromArray:tracks];
    self.downloading = YES;
    [self postProgressStatus:@"started"];
    [self startNextDownload];
}

- (void)startNextDownload {
    LTTrack *track = self.downloadQueue.firstObject;
    if (!track) {
        [self finishDownloads];
        return;
    }
    [self.downloadQueue removeObjectAtIndex:0];
    if ([self isTrackDownloaded:track]) {
        self.downloadIndex += 1;
        [self postTrackChanged:track.videoId];
        [self postProgressStatus:@"skipped"];
        [self startNextDownload];
        return;
    }
    self.downloadingVideoId = track.videoId;
    self.downloadingTrack = track;
    [self postProgressStatus:@"fetching"];
    __weak LTPlaylistStore *weakSelf = self;
    [[LTYouTubeClient sharedClient] streamURLForVideo:track.videoId completion:^(NSString *streamURL, BOOL muxedStream, NSInteger audioBitrateKbps, NSError *error) {
        LTPlaylistStore *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || !streamURL.length) {
            LTLog(@"STORE DL stream error %@ for %@", error, track.videoId);
            strongSelf.downloadingVideoId = nil;
            strongSelf.downloadingTrack = nil;
            strongSelf.downloadIndex += 1;
            [strongSelf postProgressStatus:@"error"];
            [strongSelf startNextDownload];
            return;
        }
        strongSelf.downloadingMuxed = muxedStream;
        [strongSelf recordBitrateKbps:audioBitrateKbps forVideoId:track.videoId];
        [strongSelf startDownloadURL:streamURL videoId:track.videoId];
    }];
}

- (void)startDownloadURL:(NSString *)urlString videoId:(NSString *)videoId {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                        timeoutInterval:120.0];
    [request setValue:@"bytes=0-" forHTTPHeaderField:@"Range"];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];
    self.downloadData = [NSMutableData data];
    self.downloadHTTPStatus = 0;
    self.downloadConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    LTLog(@"STORE DL start %@", videoId);
}

- (void)finishDownloads {
    self.downloading = NO;
    self.downloadConnection = nil;
    self.downloadData = nil;
    self.downloadingVideoId = nil;
    self.downloadingTrack = nil;
    [self postProgressStatus:@"finished"];
    void (^completion)(void) = self.downloadCompletion;
    self.downloadCompletion = nil;
    if (completion) completion();
}

#pragma mark - Metadata refresh

- (NSInteger)offlineTrackCount {
    NSMutableSet *ids = [NSMutableSet set];
    for (LTLocalPlaylist *playlist in self.playlists) {
        for (LTTrack *track in playlist.tracks) {
            if (!track.videoId.length) continue;
            if (![self existingLocalFilePathForVideoId:track.videoId]) continue;
            [ids addObject:track.videoId];
        }
    }
    return (NSInteger)ids.count;
}

- (void)refreshOfflineMetadataWithProgress:(void (^)(NSInteger done, NSInteger total))progress
                                completion:(void (^)(NSInteger updated, NSInteger failed))completion {
    NSMutableDictionary *byVideoId = [NSMutableDictionary dictionary];
    for (LTLocalPlaylist *playlist in self.playlists) {
        for (LTTrack *track in playlist.tracks) {
            if (!track.videoId.length) continue;
            if (![self existingLocalFilePathForVideoId:track.videoId]) continue;
            NSMutableArray *list = [byVideoId objectForKey:track.videoId];
            if (!list) {
                list = [NSMutableArray array];
                [byVideoId setObject:list forKey:track.videoId];
            }
            [list addObject:track];
        }
    }
    NSArray *videoIds = [byVideoId allKeys];
    NSInteger total = (NSInteger)videoIds.count;
    if (!total) {
        if (completion) completion(0, 0);
        return;
    }

    LTYouTubeClient *client = [LTYouTubeClient sharedClient];
    __weak LTPlaylistStore *weakSelf = self;
    __block NSInteger done = 0;
    __block NSInteger updated = 0;
    __block NSInteger failed = 0;
    __block void (^nextStep)(void);
    nextStep = ^{
        if (done >= total) {
            LTPlaylistStore *strongSelf = weakSelf;
            nextStep = nil;
            if (strongSelf) {
                [strongSelf savePlaylists];
                [strongSelf postPlaylistsChanged];
            }
            if (completion) completion(updated, failed);
            return;
        }
        NSString *videoId = [videoIds objectAtIndex:(NSUInteger)done];
        [client trackMetadataForVideoId:videoId
                             completion:^(NSString *title, NSString *artist, NSTimeInterval duration, NSString *thumbnailURL, NSError *error) {
            done += 1;
            if (error || !title.length) {
                failed += 1;
                LTLog(@"META refresh failed %@ error=%@", videoId, error);
            } else {
                updated += 1;
                for (LTTrack *track in [byVideoId objectForKey:videoId]) {
                    if (title.length) track.title = title;
                    if (artist.length) track.artist = artist;
                    if (duration > 0) track.duration = duration;
                    if (thumbnailURL.length) track.thumbnailURL = thumbnailURL;
                }
                NSString *artURL = [client highResThumbnailURL:thumbnailURL];
                [client loadImageWithURL:artURL completion:^(UIImage *image) {
                    if (image) LTLog(@"META art cached %dpx videoId=%@", (int)image.size.width, videoId);
                }];
            }
            if (progress) progress(done, total);
            nextStep();
        }];
    };
    nextStep();
}

- (void)resolveThumbnailForTrack:(LTTrack *)track
                      completion:(void (^)(NSString *thumbnailURL))completion {
    if (track.thumbnailURL.length) {
        if (completion) completion(track.thumbnailURL);
        return;
    }
    if (!track.videoId.length) {
        if (completion) completion(nil);
        return;
    }
    __weak LTPlaylistStore *weakSelf = self;
    [[LTYouTubeClient sharedClient] trackMetadataForVideoId:track.videoId
        completion:^(NSString *title, NSString *artist, NSTimeInterval duration, NSString *thumbnailURL, NSError *error) {
        __strong LTPlaylistStore *strongSelf = weakSelf;
        if (!strongSelf || !thumbnailURL.length) {
            if (completion) completion(thumbnailURL);
            return;
        }
        track.thumbnailURL = thumbnailURL;
        if (!track.title.length && title.length) track.title = title;
        if (!track.artist.length && artist.length) track.artist = artist;
        [strongSelf savePlaylists];
        LTLog(@"META resolved thumb %@ videoId=%@", thumbnailURL, track.videoId);
        if (completion) completion(thumbnailURL);
    }];
}

- (void)recordBitrateKbps:(NSInteger)kbps forVideoId:(NSString *)videoId {
    if (!videoId.length) return;
    NSMutableDictionary *rates = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"LTBitrates"] mutableCopy] ?: [NSMutableDictionary dictionary];
    [rates setObject:@(kbps) forKey:videoId];
    [[NSUserDefaults standardUserDefaults] setObject:rates forKey:@"LTBitrates"];
}

- (NSInteger)bitrateKbpsForVideoId:(NSString *)videoId {
    if (!videoId.length) return 128;
    NSDictionary *rates = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"LTBitrates"];
    id v = [rates objectForKey:videoId];
    if (!v) return 128;
    return [v integerValue];
}

- (void)postProgressStatus:(NSString *)status {
    NSDictionary *userInfo = @{
        @"status": status ?: @"",
        @"index": @(self.downloadIndex),
        @"total": @(self.downloadTotal),
        @"videoId": self.downloadingVideoId ?: @"",
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistDownloadProgressNotification
                                                        object:self
                                                      userInfo:userInfo];
}

#pragma mark - NSURLConnectionDataDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.downloadData setLength:0];
    NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
    LTLog(@"STORE DL_RESPONSE status=%d expected=%lld", (int)[http statusCode], [response expectedContentLength]);
    self.downloadHTTPStatus = [http statusCode];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.downloadData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    LTLog(@"STORE DL_ERROR %@ for %@", error, self.downloadingVideoId);
    [self postTrackChanged:self.downloadingVideoId];
    self.downloadingVideoId = nil;
    self.downloadingTrack = nil;
    self.downloadIndex += 1;
    [self postProgressStatus:@"error"];
    [self startNextDownload];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    LTLog(@"STORE DL_FINISH bytes=%d status=%d for %@", (int)self.downloadData.length, (int)self.downloadHTTPStatus, self.downloadingVideoId);
    NSString *videoId = self.downloadingVideoId;
    BOOL ok = (videoId.length && self.downloadData.length && self.downloadHTTPStatus < 400);
    if (ok) {
        NSString *path = self.downloadingMuxed
            ? [[self audioDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", videoId]]
            : [self localFilePathForVideoId:videoId];
        BOOL wrote = [self.downloadData writeToFile:path atomically:YES];
        LTLog(@"STORE saved offline %@ muxed=%d ok=%d", videoId, self.downloadingMuxed, wrote);
        if (wrote) [self addTrackToLibrary:self.downloadingTrack];
        [self postTrackChanged:videoId];
    } else {
        LTLog(@"STORE DL_FAILED status=%d bytes=%d for %@", (int)self.downloadHTTPStatus, (int)self.downloadData.length, videoId);
    }
    self.downloadingVideoId = nil;
    self.downloadingTrack = nil;
    self.downloadIndex += 1;
    [self postProgressStatus: ok ? @"downloaded" : @"error"];
    [self startNextDownload];
}

- (NSArray *)syncArrayRepresentation {
    NSMutableArray *exportArray = [NSMutableArray array];
    for (LTLocalPlaylist *playlist in self.playlists) {
        NSMutableArray *songs = [NSMutableArray array];
        for (LTTrack *track in playlist.tracks) {
            [songs addObject:@{
                @"videoId": track.videoId,
                @"title": track.title ?: @"",
                @"artist": track.artist ?: @"",
                @"album": track.album ?: @"",
                @"thumbnailURL": track.thumbnailURL ?: @"",
                @"duration": @(track.duration),
            }];
        }
        [exportArray addObject:@{
            @"id": playlist.identifier ?: @"",
            @"name": playlist.name ?: @"",
            @"description": @"",
            @"songs": songs,
            @"updatedAt": [NSDate date].description,
        }];
    }
    return exportArray;
}

// Union-merge incoming playlists by id; tracks merge by videoId.
- (NSInteger)mergeSyncArray:(NSArray *)incomingArray {
    if (![incomingArray isKindOfClass:[NSArray class]]) return 0;
    NSInteger merged = 0;
    for (NSDictionary *playlistDict in incomingArray) {
        NSString *playlistId = playlistDict[@"id"];
        NSString *name = playlistDict[@"name"];
        if (!playlistId.length || !name.length) continue;
        LTLocalPlaylist *existing = nil;
        for (LTLocalPlaylist *p in _playlists) {
            if ([p.identifier isEqualToString:playlistId]) { existing = p; break; }
        }
        BOOL created = NO;
        if (!existing) {
            existing = [[LTLocalPlaylist alloc] init];
            existing.identifier = playlistId;
            existing.name = name;
            [_playlists addObject:existing];
            created = YES;
        } else {
            existing.name = name;
        }
        NSArray *songs = playlistDict[@"songs"];
        if ([songs isKindOfClass:[NSArray class]]) {
            for (NSDictionary *songDict in songs) {
                NSString *videoId = songDict[@"videoId"];
                if (!videoId.length) continue;
                LTTrack *track = [LTTrack trackWithDictionary:songDict];
                LTTrack *haveTrack = nil;
                for (LTTrack *t in existing.tracks) {
                    if ([t.videoId isEqualToString:videoId]) { haveTrack = t; break; }
                }
                if (!haveTrack) {
                    [existing.tracks addObject:track];
                } else {
                    // Union semantics for metadata too: fill in whatever the
                    // other device knows that this copy is missing.
                    if (!haveTrack.title.length) haveTrack.title = track.title;
                    if (!haveTrack.artist.length) haveTrack.artist = track.artist;
                    if (!haveTrack.album.length) haveTrack.album = track.album;
                    if (!haveTrack.thumbnailURL.length) haveTrack.thumbnailURL = track.thumbnailURL;
                    if (haveTrack.duration <= 0 && track.duration > 0) haveTrack.duration = track.duration;
                }
            }
        }
        merged += 1;
        LTLog(@"SYNC merged %@ playlist %@", created ? @"new" : @"existing", name);
    }
    [self savePlaylists];
    [self postPlaylistsChanged];
    return merged;
}

- (BOOL)exportPlaylistsToJSONFile:(NSString *)filePath error:(NSError **)error {
    NSError *writeError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:[self syncArrayRepresentation] options:NSJSONWritingPrettyPrinted error:&writeError];
    if (!data) {
        if (error) *error = writeError;
        return NO;
    }
    BOOL ok = [data writeToFile:filePath atomically:YES];
    if (!ok && error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
    LTLog(@"STORE exported %d playlists to %@", (int)self.playlists.count, filePath);
    return ok;
}

- (BOOL)importPlaylistsFromJSONFile:(NSString *)filePath error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        return NO;
    }
    NSError *parseError = nil;
    NSArray *importArray = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    if (!importArray) {
        if (error) *error = parseError;
        return NO;
    }
    NSInteger merged = [self mergeSyncArray:importArray];
    LTLog(@"STORE imported/merged %ld playlists from %@", (long)merged, filePath);
    return YES;
}

#pragma mark - Full-state sync (phone-to-phone)

- (NSArray *)librarySyncArray {
    NSMutableArray *result = [NSMutableArray array];
    for (LTTrack *track in self.libraryTracks) {
        [result addObject:[track dictionaryRepresentation]];
    }
    return result;
}

- (NSArray *)recentsSyncArray {
    NSMutableArray *result = [NSMutableArray array];
    for (LTTrack *track in [self recentTracks]) {
        [result addObject:[track dictionaryRepresentation]];
    }
    return result;
}

- (NSDictionary *)statsSyncDict {
    NSMutableDictionary *dict = [self statsFileDict];
    NSDictionary *tracks = [dict objectForKey:@"tracks"];
    if (![tracks isKindOfClass:[NSDictionary class]]) return dict;
    // Trim the payload: only ship fields the other side needs to merge.
    NSMutableDictionary *trimmedTracks = [NSMutableDictionary dictionary];
    for (NSString *videoId in tracks) {
        NSDictionary *entry = [tracks objectForKey:videoId];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *trimmed = [NSMutableDictionary dictionary];
        trimmed[@"title"] = entry[@"title"] ?: @"";
        trimmed[@"artist"] = entry[@"artist"] ?: @"";
        trimmed[@"album"] = entry[@"album"] ?: @"";
        trimmed[@"thumbnailURL"] = entry[@"thumbnailURL"] ?: @"";
        trimmed[@"plays"] = @([[entry objectForKey:@"plays"] integerValue]);
        trimmed[@"seconds"] = @([[entry objectForKey:@"seconds"] doubleValue]);
        [trimmedTracks setObject:trimmed forKey:videoId];
    }
    [dict setObject:trimmedTracks forKey:@"tracks"];
    return dict;
}

- (NSDictionary *)syncPayload {
    return @{
        @"version": @1,
        @"deviceId": [self syncDeviceId],
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"playlists": [self syncArrayRepresentation],
        @"library": [self librarySyncArray],
        @"recents": [self recentsSyncArray],
        @"stats": [self statsSyncDict],
        @"listenedIds": [self listenedSongIDs],
    };
}

- (NSString *)syncDeviceId {
    NSString *deviceId = [[NSUserDefaults standardUserDefaults] stringForKey:@"LTSyncDeviceId"];
    if (!deviceId.length) {
        deviceId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        if (!deviceId.length) deviceId = [[NSUUID UUID] UUIDString];
        [[NSUserDefaults standardUserDefaults] setObject:deviceId forKey:@"LTSyncDeviceId"];
    }
    return deviceId;
}

- (void)mergeSyncPayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) return;
    BOOL changed = NO;

    NSArray *playlists = payload[@"playlists"];
    if ([playlists isKindOfClass:[NSArray class]]) {
        NSInteger m = [self mergeSyncArray:playlists];
        if (m > 0) changed = YES;
    }

    NSArray *library = payload[@"library"];
    if ([library isKindOfClass:[NSArray class]]) {
        for (NSDictionary *dict in library) {
            if (![dict isKindOfClass:[NSDictionary class]]) continue;
            LTTrack *track = [LTTrack trackWithDictionary:dict];
            if (!track.videoId.length) continue;
            [self addTrackToLibrary:track];
            changed = YES; // addTrackToLibrary is itself idempotent/updating
        }
    }

    NSArray *recents = payload[@"recents"];
    if ([recents isKindOfClass:[NSArray class]]) {
        // Merge recents newest-first, de-duplicating by videoId.
        NSMutableArray *merged = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *dict in recents) {
            if (![dict isKindOfClass:[NSDictionary class]]) continue;
            LTTrack *track = [LTTrack trackWithDictionary:dict];
            if (!track.videoId.length || [seen containsObject:track.videoId]) continue;
            [seen addObject:track.videoId];
            [merged addObject:[track dictionaryRepresentation]];
        }
        for (LTTrack *local in [self recentTracks]) {
            if ([seen containsObject:local.videoId]) continue;
            [seen addObject:local.videoId];
            [merged addObject:[local dictionaryRepresentation]];
        }
        if (merged.count > 20) {
            [merged removeObjectsInRange:NSMakeRange(20, merged.count - 20)];
        }
        [merged writeToFile:[self recentsFilePath] atomically:YES];
        changed = YES;
    }

    NSDictionary *stats = payload[@"stats"];
    if ([stats isKindOfClass:[NSDictionary class]]) {
        NSDictionary *incomingTracks = [stats objectForKey:@"tracks"];
        if ([incomingTracks isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *dict = [self statsFileDict];
            // Merge each incoming entry, taking the max plays/seconds so both
            // devices' listening history is preserved rather than overwritten.
            for (NSString *videoId in incomingTracks) {
                NSDictionary *incoming = [incomingTracks objectForKey:videoId];
                if (![incoming isKindOfClass:[NSDictionary class]]) continue;
                NSMutableDictionary *entry = [self statsEntryForVideoId:videoId inDict:dict];
                NSInteger inPlays = [[incoming objectForKey:@"plays"] integerValue];
                NSInteger localPlays = [[entry objectForKey:@"plays"] integerValue];
                if (inPlays > localPlays) [entry setObject:@(inPlays) forKey:@"plays"];
                double inSeconds = [[incoming objectForKey:@"seconds"] doubleValue];
                double localSeconds = [[entry objectForKey:@"seconds"] doubleValue];
                if (inSeconds > localSeconds) [entry setObject:@(inSeconds) forKey:@"seconds"];
                // Fill missing metadata.
                if (![[entry objectForKey:@"title"] length]) [entry setObject:incoming[@"title"] ?: @"" forKey:@"title"];
                if (![[entry objectForKey:@"artist"] length]) [entry setObject:incoming[@"artist"] ?: @"" forKey:@"artist"];
                if (![[entry objectForKey:@"album"] length]) [entry setObject:incoming[@"album"] ?: @"" forKey:@"album"];
                if (![[entry objectForKey:@"thumbnailURL"] length]) [entry setObject:incoming[@"thumbnailURL"] ?: @"" forKey:@"thumbnailURL"];
            }
            [self writeStatsFileDict:dict];
            changed = YES;
        }
    }

    NSArray *listenedIds = payload[@"listenedIds"];
    if ([listenedIds isKindOfClass:[NSArray class]]) {
        NSMutableArray *ids = [NSMutableArray arrayWithArray:[self listenedSongIDs]];
        BOOL idChanged = NO;
        for (NSObject *obj in listenedIds) {
            if (![obj isKindOfClass:[NSString class]]) continue;
            NSString *vid = (NSString *)obj;
            if (vid.length && ![ids containsObject:vid]) {
                [ids addObject:vid];
                idChanged = YES;
            }
        }
        if (idChanged) {
            [[NSUserDefaults standardUserDefaults] setObject:ids forKey:kLTListenedSongIDsKey];
            changed = YES;
        }
    }

    [self postPlaylistsChanged];
    if (changed) {
        LTLog(@"SYNC merged full payload (%d playlists)", (int)self.playlists.count);
    }
}

@end
