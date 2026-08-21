#import "LTPlaylistStore.h"
#import "LTYouTubeClient.h"
#import "LTLog.h"

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
@property (nonatomic, assign) BOOL downloadingMuxed;
@property (nonatomic, assign) NSInteger downloadHTTPStatus;
@property (nonatomic, assign) NSInteger downloadTotal;
@property (nonatomic, assign) NSInteger downloadIndex;
@property (nonatomic, copy) void (^downloadCompletion)(void);
@property (nonatomic, assign) BOOL downloading;
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
        [self ensureDirectories];
        [self loadPlaylists];
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
    NSMutableArray *plist = [NSMutableArray array];
    [plist addObject:[track dictionaryRepresentation]];
    NSInteger count = 1;
    for (LTTrack *old in [self recentTracks]) {
        if ([old.videoId isEqualToString:track.videoId]) continue;
        [plist addObject:[old dictionaryRepresentation]];
        count += 1;
        if (count >= 3) break;
    }
    [plist writeToFile:[self recentsFilePath] atomically:YES];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTRecentsDidChangeNotification object:self];
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
    [self postProgressStatus:@"fetching"];
    __weak LTPlaylistStore *weakSelf = self;
    [[LTYouTubeClient sharedClient] streamURLForVideo:track.videoId completion:^(NSString *streamURL, BOOL muxedStream, NSError *error) {
        LTPlaylistStore *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || !streamURL.length) {
            LTLog(@"STORE DL stream error %@ for %@", error, track.videoId);
            strongSelf.downloadingVideoId = nil;
            strongSelf.downloadIndex += 1;
            [strongSelf postProgressStatus:@"error"];
            [strongSelf startNextDownload];
            return;
        }
        strongSelf.downloadingMuxed = muxedStream;
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
        [self postTrackChanged:videoId];
    } else {
        LTLog(@"STORE DL_FAILED status=%d bytes=%d for %@", (int)self.downloadHTTPStatus, (int)self.downloadData.length, videoId);
    }
    self.downloadingVideoId = nil;
    self.downloadIndex += 1;
    [self postProgressStatus: ok ? @"downloaded" : @"error"];
    [self startNextDownload];
}

@end
