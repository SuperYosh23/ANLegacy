#import "LTPlaylistStore.h"
#import "S6JSON.h"
#import "LTYouTubeClient.h"
#import "S6HTTPRequest.h"
#import "LTLog.h"
// For LTDataDirectory(), the root of all app storage.
#import "LTFilePaths.h"
#import <objc/runtime.h>

// Per-cell marker of which playlist a row is showing, so a late artwork reply
// for one row cannot be written onto another. See +providePlaylistArtwork:.
static const void *kLTPlaylistArtTokenKey = &kLTPlaylistArtTokenKey;

// iOS 6+ only has NSUUID; CoreFoundation's CFUUID works all the way back to
// iOS 2.0, so use it unconditionally for identifiers (stations, sync device).
static NSString *LTGenerateUUIDString(void) {
    CFUUIDRef uuid = CFUUIDCreate(NULL);
    NSString *string = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, uuid);
    CFRelease(uuid);
    return string;
}

#define kLTListenedSongIDsKey @"LTListenedSongIDs2"

NSString *const LTPlaylistsDidChangeNotification = @"LTPlaylistsDidChangeNotification";
NSString *const LTPlaylistTrackDidChangeNotification = @"LTPlaylistTrackDidChangeNotification";
NSString *const LTPlaylistDownloadProgressNotification = @"LTPlaylistDownloadProgressNotification";
NSString *const LTRecentsDidChangeNotification = @"LTRecentsDidChangeNotification";

// Internal queue entry: one pending track plus the batch it belongs to, so a
// caller's completion can fire exactly once when all of *its* tracks are done.
@interface LTDownloadBatch : NSObject
@property (nonatomic, assign) NSInteger remaining;
@property (nonatomic, copy) void (^completion)(void);
@end

@implementation LTDownloadBatch
@end

@interface LTDownloadItem : NSObject
@property (nonatomic, strong) LTTrack *track;
@property (nonatomic, strong) LTDownloadBatch *batch;
@end

@implementation LTDownloadItem
@end

@interface LTPlaylistStore () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSMutableArray *playlists;
@property (nonatomic, strong) NSMutableArray *stations;
// Persistent pending queue (LTDownloadItem). Survives relaunch.
@property (nonatomic, strong) NSMutableArray *downloadQueue;
@property (nonatomic, strong) NSURLConnection *downloadConnection;
@property (nonatomic, strong) S6HTTPRequest *downloadS6Request;
@property (nonatomic, strong) NSMutableData *downloadData;
@property (nonatomic, copy) NSString *downloadingVideoId;
@property (nonatomic, strong) LTTrack *downloadingTrack;
@property (nonatomic, assign) BOOL downloadingMuxed;
@property (nonatomic, assign) NSInteger downloadHTTPStatus;
@property (nonatomic, assign) NSInteger downloadTotal;
@property (nonatomic, assign) NSInteger downloadIndex;
@property (nonatomic, assign) NSInteger downloadRunTotal;
@property (nonatomic, assign) NSInteger downloadRunCompleted;
@property (nonatomic, copy) void (^downloadCompletion)(void);
@property (nonatomic, assign) BOOL downloading;
@property (nonatomic, strong) LTDownloadItem *activeItem;
@property (nonatomic, assign) NSInteger downloadFailedCount;
@property (nonatomic, assign) BOOL downloadCancelled;
@property (nonatomic, assign) BOOL downloadCancelling;
@property (nonatomic, strong) NSMutableArray *libraryTracks;
@property (nonatomic, strong) NSMutableDictionary *artistAvatarURLs;
// Listening-stats ledger held in memory so the 5-second playback commit does not
// re-parse and re-serialise a file that grows with every track ever played.
// See -statsFileDict and -writeStatsFileDict:.
@property (nonatomic, strong) NSMutableDictionary *statsCache;
@property (nonatomic, assign) BOOL statsDirty;
@property (nonatomic, assign) BOOL statsFlushScheduled;
// Recently played, parsed once. Invalidated wherever recents.plist is written;
// see -recentTracks.
@property (nonatomic, strong) NSArray *recentsCache;
@end

@implementation LTStatsEntry
@end

#pragma mark - Duplicate-name guard


// Drives a per-song duplicate confirmation. UIAlertView keeps only a weak
// delegate reference, so one long-lived instance acts as the delegate for every
// prompt and carries the pending batch on the side.
//
// The prompt is per song rather than per batch on purpose: with an album of 30
// tracks, "3 tracks share a name with tracks already in this playlist" forces
// the listener to decide about the whole album at once, including the 27 they
// never looked at. Asking one at a time keeps each decision about one song, and
// "Don't Add" means exactly that one song.
//
// Only one batch is in flight at a time. Reaching this with a second batch
// already up is not possible through the UI (the picker has to be dismissed
// before Add All can be tapped again), so it is ignored rather than stacked.
@interface LTDuplicatePrompt : NSObject <UIAlertViewDelegate>
@property (nonatomic, strong) LTLocalPlaylist *playlist;
// Duplicate tracks still awaiting an answer, in the order they were found.
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic, copy) void (^completion)(NSInteger);
@property (nonatomic, assign) NSInteger addedCount;
@property (nonatomic, assign) BOOL inFlight;
+ (instancetype)shared;
- (void)startWithQueue:(NSArray *)duplicates
              playlist:(LTLocalPlaylist *)playlist
             presenter:(UIViewController *)presenter
           addedSoFar:(NSInteger)addedSoFar
            completion:(void (^)(NSInteger addedCount))completion;
@end

@implementation LTDuplicatePrompt

+ (instancetype)shared {
    static LTDuplicatePrompt *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[LTDuplicatePrompt alloc] init]; });
    return shared;
}

- (void)startWithQueue:(NSArray *)duplicates
              playlist:(LTLocalPlaylist *)playlist
             presenter:(UIViewController *)presenter
           addedSoFar:(NSInteger)addedSoFar
            completion:(void (^)(NSInteger addedCount))completion {
    if (self.inFlight) {
        LTLog(@"DUPLICATE prompt already in flight; ignoring extra batch");
        return;
    }
    self.playlist = playlist;
    self.queue = [NSMutableArray arrayWithArray:duplicates];
    self.completion = completion;
    self.addedCount = addedSoFar;
    self.inFlight = YES;

    // Presenting controller is gone: nobody can answer, so treat every remaining
    // duplicate as "Don't Add" rather than raising a dialog into a dead flow.
    if (presenter && !presenter.view) { [self finish]; return; }
    [self presentNext];
}

- (void)presentNext {
    if (!self.queue.count) { [self finish]; return; }
    LTTrack *track = [self.queue objectAtIndex:0];

    // Name the clash on both sides so the listener can tell "same song twice"
    // apart from "a different cut that happens to share a name".
    NSString *existing = [self existingTitleForTrack:track];
    NSString *message;
    if (existing.length) {
        message = [NSString stringWithFormat:
                   @"\"%@\" is already in \"%@\" as \"%@\".\n\n"
                   @"That is a different recording with the same name. Add it anyway?",
                   track.title ?: @"This track", self.playlist.name, existing];
    } else {
        message = [NSString stringWithFormat:
                   @"\"%@\" is already in \"%@\".\n\n"
                   @"That is a different recording with the same name. Add it anyway?",
                   track.title ?: @"This track", self.playlist.name];
    }

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Duplicate Name"
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"Don't Add"
                                          otherButtonTitles:@"Add Anyway", nil];
    // UIAlertView only offers -show; there is no -showInView:.
    [alert show];
}

// The already-present track whose title this one collides with, for the message.
- (NSString *)existingTitleForTrack:(LTTrack *)track {
    for (LTTrack *existing in self.playlist.tracks) {
        if ([track.title caseInsensitiveCompare:existing.title] == NSOrderedSame) return existing.title;
    }
    return nil;
}

- (void)finish {
    self.inFlight = NO;
    self.queue = nil;
    self.playlist = nil;
    void (^completion)(NSInteger) = self.completion;
    self.completion = nil;
    NSInteger added = self.addedCount;
    self.addedCount = 0;
    if (completion) completion(added);
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (!self.inFlight || !self.queue.count) return;
    LTTrack *track = [self.queue objectAtIndex:0];
    // 0 is "Don't Add"; anything else means the listener chose "Add Anyway".
    if (buttonIndex != 0) {
        [[LTPlaylistStore sharedStore] addTrack:track toPlaylist:self.playlist];
        self.addedCount++;
    }
    [self.queue removeObjectAtIndex:0];
    [self presentNext];
}

@end

#pragma mark - Duplicate-name guard

// Delete confirmation. Same shape as LTDuplicatePrompt and for the same reason:
// UIAlertView holds its delegate weakly, so a long-lived object has to stand in
// for it and carry the pending action. Keeping it here rather than in each of
// the three controllers that can delete a playlist also means one implementation
// of the wording and no risk of two controllers claiming the same alert tag.
@interface LTPlaylistDeletePrompt : NSObject <UIAlertViewDelegate>
@property (nonatomic, strong) LTLocalPlaylist *playlist;
@property (nonatomic, copy) void (^completion)(BOOL);
@property (nonatomic, assign) BOOL inFlight;
+ (instancetype)shared;
- (void)askToDelete:(LTLocalPlaylist *)playlist completion:(void (^)(BOOL deleted))completion;
@end

@implementation LTPlaylistDeletePrompt

+ (instancetype)shared {
    static LTPlaylistDeletePrompt *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[LTPlaylistDeletePrompt alloc] init]; });
    return shared;
}

- (void)askToDelete:(LTLocalPlaylist *)playlist completion:(void (^)(BOOL deleted))completion {
    // A second swipe while a prompt is already up is not reachable through the
    // UI (the row stays until the prompt resolves), so ignore rather than stack.
    if (self.inFlight) {
        LTLog(@"DELETE prompt already in flight; ignoring");
        if (completion) completion(NO);
        return;
    }

    NSString *message;
    NSInteger count = (NSInteger)playlist.tracks.count;
    if (count == 0) {
        message = [NSString stringWithFormat:@"\"%@\" will be deleted.", playlist.name];
    } else {
        message = [NSString stringWithFormat:
                   @"\"%@\" and its %d song%@ will be permanently deleted.",
                   playlist.name, (int)count, count == 1 ? @"" : @"s"];
    }

    self.playlist = playlist;
    self.completion = completion;
    self.inFlight = YES;

    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Delete Playlist?"
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Delete", nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (!self.inFlight) return;
    self.inFlight = NO;
    LTLocalPlaylist *playlist = self.playlist;
    void (^completion)(BOOL) = self.completion;
    self.playlist = nil;
    self.completion = nil;

    BOOL deleted = NO;
    if (buttonIndex != 0 && playlist) {
        [[LTPlaylistStore sharedStore] deletePlaylist:playlist];
        deleted = YES;
        LTLog(@"DELETE confirmed playlist %@", playlist.name);
    }
    if (completion) completion(deleted);
}

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
        _stations = [NSMutableArray array];
        _downloadQueue = [NSMutableArray array];
        _libraryTracks = [NSMutableArray array];
        _artistAvatarURLs = [NSMutableDictionary dictionary];
        [self ensureDirectories];
        [self loadPlaylists];
        [self loadStations];
        [self loadLibrary];
        [self loadArtistAvatars];
        [self loadDownloadQueue];
    }
    return self;
}

// The engine is "busy" from the caller's point of view while a transfer is in
// flight, but an idle persisted queue must not count as busy or resume would be
// a no-op.
- (BOOL)isDownloadBusy {
    return self.downloading;
}

- (NSString *)baseDirectory {
    return LTDataDirectory();
}

- (NSString *)audioDirectory {
    return [self.baseDirectory stringByAppendingPathComponent:@"audio"];
}

- (NSString *)artDirectory {
    return [self.baseDirectory stringByAppendingPathComponent:@"art"];
}

// Lyrics are cached here so they survive relaunches and work with no network.
// Without this, every track change paid a round-trip and offline always ended
// in "No lyrics available".
- (NSString *)lyricsDirectory {
    return [self.baseDirectory stringByAppendingPathComponent:@"lyrics"];
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
    error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[self lyricsDirectory]
                              withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) LTLog(@"STORE mkdir lyrics error: %@", error);
}

#pragma mark - Lyrics cache

// Filenames come from the video id, which is a fixed YouTube charset, so it is
// safe to use directly -- but strip anything unexpected anyway rather than let a
// stray "/" turn into a path traversal.
- (NSString *)lyricsCachePathForVideoId:(NSString *)videoId {
    NSMutableString *safe = [NSMutableString stringWithCapacity:videoId.length];
    for (NSUInteger i = 0; i < videoId.length; i++) {
        unichar c = [videoId characterAtIndex:i];
        BOOL ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') || c == '-' || c == '_';
        if (ok) [safe appendFormat:@"%C", c];
    }
    if (!safe.length) return nil;
    return [[[self lyricsDirectory] stringByAppendingPathComponent:safe]
            stringByAppendingPathExtension:@"json"];
}

- (NSDictionary *)cachedLyricsForVideoId:(NSString *)videoId {
    if (!videoId.length) return nil;
    NSString *path = [self lyricsCachePathForVideoId:videoId];
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    id json = [S6JSON objectWithData:data error:NULL];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

- (void)cacheLyrics:(NSDictionary *)payload forVideoId:(NSString *)videoId {
    if (!videoId.length) return;
    NSString *path = [self lyricsCachePathForVideoId:videoId];
    if (!path) return;

    // An empty dictionary is a meaningful result: "this song has no lyrics".
    // Recording it stops us re-fetching on every play for songs that will never
    // have any.
    NSDictionary *body = [payload isKindOfClass:[NSDictionary class]] ? payload : [NSDictionary dictionary];
    NSData *data = [S6JSON dataWithObject:body error:NULL];
    if (!data) return;

    NSError *error = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
        LTLog(@"LYRICS cache write failed for %@: %@", videoId, error);
    }
}

- (void)clearLyricsCache {
    NSString *dir = [self lyricsDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
    for (NSString *name in names) {
        if ([name hasSuffix:@".json"]) [fm removeItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL];
    }
    LTLog(@"LYRICS cache cleared (%lu files)", (unsigned long)[names count]);
}

- (unsigned long long)lyricsCacheSize {
    NSString *dir = [self lyricsDirectory];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:dir error:NULL];
    unsigned long long total = 0;
    for (NSString *name in names) {
        NSDictionary *attrs = [fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:name] error:NULL];
        if (attrs) total += [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
    }
    return total;
}

- (NSString *)playlistsFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"playlists.plist"];
}

- (NSString *)stationsFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"stations.plist"];
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

- (void)loadStations {
    NSArray *plist = [NSArray arrayWithContentsOfFile:[self stationsFilePath]];
    if (![plist isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *dict in plist) {
        LTStation *station = [LTStation stationWithDictionary:dict];
        if (station.identifier.length) [_stations addObject:station];
    }
    LTLog(@"STORE loaded %d stations", (int)self.stations.count);
}

- (void)savePlaylists {
    NSMutableArray *plist = [NSMutableArray array];
    for (LTLocalPlaylist *playlist in self.playlists) {
        [plist addObject:[playlist dictionaryRepresentation]];
    }
    BOOL ok = [plist writeToFile:[self playlistsFilePath] atomically:YES];
    if (!ok) LTLog(@"STORE save failed");
}

- (void)saveStations {
    NSMutableArray *plist = [NSMutableArray array];
    for (LTStation *station in self.stations) {
        [plist addObject:[station dictionaryRepresentation]];
    }
    BOOL ok = [plist writeToFile:[self stationsFilePath] atomically:YES];
    if (!ok) LTLog(@"STORE save failed");
}

- (void)postPlaylistsChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:self];
}

#pragma mark - Artist avatars

- (NSString *)artistAvatarsFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"artistAvatars.plist"];
}

- (void)loadArtistAvatars {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[self artistAvatarsFilePath]];
    if ([plist isKindOfClass:[NSDictionary class]]) {
        [_artistAvatarURLs addEntriesFromDictionary:plist];
    }
    LTLog(@"STORE loaded %d artist avatars", (int)_artistAvatarURLs.count);
}

- (void)saveArtistAvatars {
    [_artistAvatarURLs writeToFile:[self artistAvatarsFilePath] atomically:YES];
}

- (NSString *)artistAvatarKeyForName:(NSString *)name {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [trimmed lowercaseString];
}

- (NSString *)artistAvatarURLForName:(NSString *)name {
    if (!name.length) return nil;
    return [_artistAvatarURLs objectForKey:[self artistAvatarKeyForName:name]];
}

- (void)setArtistAvatarURL:(NSString *)url forName:(NSString *)name {
    if (!name.length || !url.length) return;
    [_artistAvatarURLs setObject:url forKey:[self artistAvatarKeyForName:name]];
    [self saveArtistAvatars];
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
    for (LTTrack *track in [self.libraryTracks copy]) {
        [plist addObject:[track dictionaryRepresentation]];
    }
    [plist writeToFile:[self libraryFilePath] atomically:YES];
}

- (void)addTrackToLibrary:(LTTrack *)track {
    if (!track.videoId.length) return;
    for (LTTrack *existing in [self.libraryTracks copy]) {
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

- (void)removeTrackFromLibrary:(LTTrack *)track {
    if (!track.videoId.length) return;
    LTTrack *match = nil;
    for (LTTrack *existing in [_libraryTracks copy]) {
        if ([existing.videoId isEqualToString:track.videoId]) { match = existing; break; }
    }
    if (!match) return;
    [_libraryTracks removeObject:match];
    [self saveLibrary];
    [self postPlaylistsChanged];
    LTLog(@"STORE removed %@ from library", track.videoId);
}

- (NSArray *)stations {
    return [_stations copy];
}

- (LTStation *)createStationWithName:(NSString *)name seeds:(NSArray *)seeds {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) trimmed = @"New Station";
    LTStation *station = [[LTStation alloc] init];
    station.identifier = LTGenerateUUIDString();
    station.name = trimmed;
    station.seeds = [seeds mutableCopy] ?: [NSMutableArray array];
    [_stations addObject:station];
    [self saveStations];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:self];
    return station;
}

- (void)deleteStation:(LTStation *)station {
    if (!station) return;
    [_stations removeObject:station];
    [self saveStations];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:self];
}

- (void)renameStation:(LTStation *)station name:(NSString *)name {
    if (!station) return;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return;
    station.name = trimmed;
    [self saveStations];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:self];
}

- (void)setCoverImage:(UIImage *)image forStation:(LTStation *)station {
    if (!station.identifier.length) return;
    // Remove old cover if exists
    if (station.coverPath.length) {
        [[NSFileManager defaultManager] removeItemAtPath:station.coverPath error:nil];
        station.coverPath = nil;
    }
    if (image) {
        NSString *path = [[self artDirectory] stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"station-cover-%@.jpg", station.identifier]];
        NSData *data = UIImageJPEGRepresentation(image, 0.85);
        if (data) {
            [data writeToFile:path atomically:YES];
            station.coverPath = path;
            LTLog(@"STORE saved cover for station %@ at %@", station.name, path);
        }
    }
    [self saveStations];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistsDidChangeNotification object:self];
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

+ (BOOL)providePlaylistArtwork:(LTLocalPlaylist *)playlist toCell:(UITableViewCell *)cell {
    if (!cell) return YES;
    // An associated-object token, as in -loadArtworkURL:intoCell:, so a reply
    // for one row cannot land on another.
    if (playlist.coverPath.length) {
        objc_setAssociatedObject(cell, kLTPlaylistArtTokenKey, playlist.identifier ?: @"",
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        cell.imageView.image = [UIImage imageWithContentsOfFile:playlist.coverPath];
        return YES;
    }
    if (!playlist.tracks.count) return YES;
    LTTrack *first = [playlist.tracks objectAtIndex:0];
    if (!first.thumbnailURL.length) return YES;

    NSString *token = playlist.identifier.length ? playlist.identifier : (first.thumbnailURL ?: @"");
    objc_setAssociatedObject(cell, kLTPlaylistArtTokenKey, token, OBJC_ASSOCIATION_COPY_NONATOMIC);
    cell.imageView.image = nil;

    // Retain the cell for the duration of the load: an unsafe-unretained cell
    // can be deallocated after scrolling, and the late reply then writes into
    // freed memory. The token check still prevents cross-row artwork.
    [[LTYouTubeClient sharedClient] loadImageWithURL:first.thumbnailURL completion:^(UIImage *image) {
        UITableViewCell *strongCell = cell;
        if (!strongCell || !image) return;
        NSString *current = objc_getAssociatedObject(strongCell, kLTPlaylistArtTokenKey);
        if (![current isEqualToString:token]) return; // recycled onto another row
        strongCell.imageView.image = image;
        // Keep it, so this row never has to go back to the network for art.
        [[LTPlaylistStore sharedStore] cacheDerivedCoverImage:image forPlaylist:playlist];
    }];
    return NO;
}

- (void)cacheDerivedCoverImage:(UIImage *)image forPlaylist:(LTLocalPlaylist *)playlist {
    if (!image || !playlist.identifier.length) return;
    if (playlist.coverPath.length) return; // a cover is already set
    NSString *path = [[self artDirectory] stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"cover-%@.jpg", playlist.identifier]];
    NSData *data = UIImageJPEGRepresentation(image, 0.85);
    if (!data.length) return;
    // Another list may have derived a cover for this playlist while this
    // fetch was in flight.
    if (playlist.coverPath.length) return;
    [data writeToFile:path atomically:YES];
    playlist.coverPath = path;
    [self savePlaylists]; // no notification: this runs during cell rendering
    LTLog(@"STORE cached derived cover for playlist %@", playlist.name);
}

- (void)addTrack:(LTTrack *)track toPlaylist:(LTLocalPlaylist *)playlist {
    if (!track.videoId.length) return;

    BOOL alreadyInPlaylist = NO;
    for (LTTrack *existing in playlist.tracks) {
        if ([existing.videoId isEqualToString:track.videoId]) { alreadyInPlaylist = YES; break; }
    }

    if (!alreadyInPlaylist) {
        [playlist.tracks addObject:track];
        [self savePlaylists];
        LTLog(@"STORE added track %@ to %@", track.videoId, playlist.name);
    }

    // Putting a song in a playlist means it belongs to you, so it goes to the
    // library too. Previously only a completed download did that, which left a
    // playlist you had deliberately assembled missing from Library. This runs
    // even when the track was already in the playlist: playlists created before
    // this behaviour existed can hold tracks the library has never seen.
    [self addTrackToLibrary:track];
    [self postPlaylistsChanged];
}

- (void)removeTrackAtIndex:(NSInteger)index fromPlaylist:(LTLocalPlaylist *)playlist {
    if (index < 0 || index >= (NSInteger)playlist.tracks.count) return;
    [playlist.tracks removeObjectAtIndex:(NSUInteger)index];
    [self savePlaylists];
    [self postPlaylistsChanged];
}

+ (NSArray *)duplicateTitledTracks:(NSArray *)tracks inPlaylist:(LTLocalPlaylist *)playlist {
    NSMutableArray *duplicates = [NSMutableArray array];
    if (!playlist.tracks.count) return duplicates;
    for (LTTrack *candidate in tracks) {
        if (![candidate isKindOfClass:[LTTrack class]]) continue;
        NSString *title = candidate.title;
        if (!title.length) continue;
        for (LTTrack *existing in playlist.tracks) {
            if ([title caseInsensitiveCompare:existing.title] == NSOrderedSame) {
                [duplicates addObject:candidate];
                break;
            }
        }
    }
    return duplicates;
}

+ (void)confirmDeletePlaylist:(LTLocalPlaylist *)playlist
                  presenting:(UIViewController *)presenter
                  completion:(void (^)(BOOL deleted))completion {
    if (!playlist) {
        if (completion) completion(NO);
        return;
    }
    if (presenter && !presenter.view) {
        // The controller went away behind the prompt; do not raise a dialog
        // into a dead flow.
        if (completion) completion(NO);
        return;
    }
    [[LTPlaylistDeletePrompt shared] askToDelete:playlist completion:completion];
}

+ (void)addTracks:(NSArray *)tracks
      toPlaylist:(LTLocalPlaylist *)playlist
   confirmingFrom:(UIViewController *)presenter
      completion:(void (^)(NSInteger addedCount))completion {
    if (!playlist || !tracks.count) {
        if (completion) completion(0);
        return;
    }

    NSArray *duplicates = [self duplicateTitledTracks:tracks inPlaylist:playlist];

    // Everything with a new name goes in straight away; only the name clashes
    // need a decision. Asking about the whole batch would mean answering for
    // tracks that were never in question.
    NSInteger added = 0;
    for (LTTrack *track in tracks) {
        if (![track isKindOfClass:[LTTrack class]]) continue;
        if ([duplicates containsObject:track]) continue;
        [[LTPlaylistStore sharedStore] addTrack:track toPlaylist:playlist];
        added++;
    }

    if (!duplicates.count) {
        if (completion) completion(added);
        return;
    }

    // One prompt per clashing track, walked in order by LTDuplicatePrompt. The
    // completion fires after the last of them is answered, not before.
    [[LTDuplicatePrompt shared] startWithQueue:duplicates
                                      playlist:playlist
                                     presenter:presenter
                                   addedSoFar:added
                                    completion:completion];
}

+ (void)addTrack:(LTTrack *)track
     toPlaylist:(LTLocalPlaylist *)playlist
  confirmingFrom:(UIViewController *)presenter
      completion:(void (^)(BOOL added))completion {
    if (!track) {
        if (completion) completion(NO);
        return;
    }
    [self addTracks:@[track] toPlaylist:playlist confirmingFrom:presenter completion:^(NSInteger added) {
        if (completion) completion(added > 0);
    }];
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

// Recently played, newest first, capped at 20.
//
// Cached in memory. This re-read and re-parsed recents.plist and rebuilt 20
// LTTrack objects on every call, and it is called on every Home tab switch, on
// every recents-changed notification, and twice per track change (once here to
// rewrite the file, once via the notification). There are only two writers of
// the file in this class, -recordRecentTrack: and -mergeSyncPayload:, and both
// now drop the cache, so a stale recents list is not possible.
- (NSArray *)recentTracks {
    if (_recentsCache) return _recentsCache;
    NSArray *plist = [NSArray arrayWithContentsOfFile:[self recentsFilePath]];
    NSMutableArray *tracks = [NSMutableArray array];
    if ([plist isKindOfClass:[NSArray class]]) {
        for (NSDictionary *dict in plist) {
            LTTrack *track = [LTTrack trackWithDictionary:dict];
            if (track.videoId.length) [tracks addObject:track];
        }
    }
    _recentsCache = tracks;
    return _recentsCache;
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
    // Drop the cached list; the next -recentTracks re-reads what was just written.
    _recentsCache = nil;
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
    if (![terms isKindOfClass:[NSArray class]]) return [NSArray array];
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

- (void)clearRecents {
    [[NSFileManager defaultManager] removeItemAtPath:[self recentsFilePath] error:nil];
    _recentsCache = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:LTRecentsDidChangeNotification object:self];
}

#pragma mark - Listening stats

- (NSString *)statsFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"stats.plist"];
}

// The stats ledger, cached in memory.
//
// WHY: playback commits listening time on a 5-second timer, and each commit used
// to re-read and re-parse the entire plist, mutate it, then serialise and write
// it back atomically (temp file + rename). The file grows by one entry per track
// ever played, so that got steadily more expensive and ran on the main thread
// during playback: a visible hitch every five seconds on a 3GS.
//
// Every read and every write in this file already goes through these two
// methods, so holding the dictionary here keeps them consistent, including the
// P2P sync merge paths further down.
//
// DURABILITY: writes are debounced rather than deferred indefinitely. The ledger
// is small and this is a local file, so a short coalescing window plus a flush on
// background is indistinguishable in practice from writing every time, and
// -flushStatsNow is also called from the app delegate on the way out.
- (NSMutableDictionary *)statsFileDict {
    @synchronized (self) {
        if (!_statsCache) {
            NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:[self statsFilePath]];
            _statsCache = ([dict isKindOfClass:[NSDictionary class]]
                           ? [NSMutableDictionary dictionaryWithDictionary:dict]
                           : [NSMutableDictionary dictionary]);
        }
        return _statsCache;
    }
}

- (void)writeStatsFileDict:(NSDictionary *)dict {
    @synchronized (self) {
        // Most callers pass back the very object -statsFileDict handed them and
        // mutated in place, which is the common case now. Copy it only when it
        // is genuinely a different dictionary: copying on every 5-second commit
        // would deep-copy the whole ledger, which is the cost being removed here.
        if (dict == _statsCache) {
            // already the live cache
        } else if ([dict isKindOfClass:[NSDictionary class]]) {
            _statsCache = [dict mutableCopy];
        } else {
            _statsCache = [NSMutableDictionary dictionary];
        }
        _statsDirty = YES;
    }
    [self scheduleStatsFlush];
}

// Coalesces bursts of writes into one. A pending flush is rescheduled rather
// than stacked, so a track change followed by three commits still writes once.
- (void)scheduleStatsFlush {
    @synchronized (self) {
        if (!_statsFlushScheduled) {
            _statsFlushScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self flushStatsNow];
            });
        }
    }
}

- (void)flushStatsNow {
    NSDictionary *snapshot = nil;
    @synchronized (self) {
        _statsFlushScheduled = NO;
        if (!_statsDirty || !_statsCache) return;
        _statsDirty = NO;
        snapshot = [_statsCache copy];
    }
    // Serialise off the main thread. `snapshot` is an immutable copy, so the
    // write cannot race a later mutation of the live cache.
    NSString *path = [self statsFilePath];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        if (![snapshot writeToFile:path atomically:YES]) {
            LTLog(@"STATS write failed");
        }
    });
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

- (void)flushListeningStats {
    [self flushStatsNow];
}

- (void)clearListeningStats {
    [[NSFileManager defaultManager] removeItemAtPath:[self statsFilePath] error:nil];
    @synchronized (self) {
        // Drop the in-memory ledger too, and cancel any pending flush: otherwise
        // the next read repopulates the cache from the deleted data and a
        // scheduled flush writes it straight back.
        _statsCache = nil;
        _statsDirty = NO;
        _statsFlushScheduled = NO;
    }
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kLTListenedSongIDsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:LTRecentsDidChangeNotification object:self];
}

- (NSArray *)statsEntries {
    NSMutableDictionary *dict = [self statsFileDict];
    NSDictionary *tracks = [dict objectForKey:@"tracks"];
    if (![tracks isKindOfClass:[NSDictionary class]]) tracks = [NSDictionary dictionary];

    NSMutableDictionary *combined = [NSMutableDictionary dictionary];
    for (NSString *videoId in tracks) {
        NSDictionary *data = [tracks objectForKey:videoId];
        if (![data isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:data];
        [combined setObject:entry forKey:videoId];
    }

    NSDictionary *received = [dict objectForKey:@"received"];
    if ([received isKindOfClass:[NSDictionary class]]) {
        for (NSString *fromDevice in received) {
            // Heal old self-sync corruption (a ledger entry pointing at our own
            // device id holding a copy of our own stats): ignore it so it can't
            // keep inflating the displayed totals.
            if ([fromDevice isEqualToString:[self syncDeviceId]]) continue;
            NSDictionary *peer = [received objectForKey:fromDevice];
            if (![peer isKindOfClass:[NSDictionary class]]) continue;
            for (NSString *videoId in peer) {
                NSDictionary *remote = [peer objectForKey:videoId];
                if (![remote isKindOfClass:[NSDictionary class]]) continue;
                NSMutableDictionary *entry = [combined objectForKey:videoId];
                if (!entry) {
                    entry = [NSMutableDictionary dictionary];
                    [entry setObject:[remote objectForKey:@"title"] ?: @"" forKey:@"title"];
                    [entry setObject:[remote objectForKey:@"artist"] ?: @"" forKey:@"artist"];
                    [entry setObject:[remote objectForKey:@"album"] ?: @"" forKey:@"album"];
                    [entry setObject:[remote objectForKey:@"thumbnailURL"] ?: @"" forKey:@"thumbnailURL"];
                    [entry setObject:@(0) forKey:@"plays"];
                    [entry setObject:@(0.0) forKey:@"seconds"];
                    [combined setObject:entry forKey:videoId];
                }
                if (![[entry objectForKey:@"title"] length]) [entry setObject:[remote objectForKey:@"title"] ?: @"" forKey:@"title"];
                if (![[entry objectForKey:@"artist"] length]) [entry setObject:[remote objectForKey:@"artist"] ?: @"" forKey:@"artist"];
                if (![[entry objectForKey:@"album"] length]) [entry setObject:[remote objectForKey:@"album"] ?: @"" forKey:@"album"];
                if (![[entry objectForKey:@"thumbnailURL"] length]) [entry setObject:[remote objectForKey:@"thumbnailURL"] ?: @"" forKey:@"thumbnailURL"];
                [entry setObject:@([[entry objectForKey:@"plays"] integerValue] + [[remote objectForKey:@"plays"] integerValue]) forKey:@"plays"];
                [entry setObject:@([[entry objectForKey:@"seconds"] doubleValue] + [[remote objectForKey:@"seconds"] doubleValue]) forKey:@"seconds"];
            }
        }
    }

    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *videoId in combined) {
        NSDictionary *data = [combined objectForKey:videoId];
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

- (NSArray *)topPlayedTracks:(NSInteger)count {
    NSArray *entries = [self mostPlayedTracks];
    NSMutableArray *out = [NSMutableArray array];
    for (id e in entries) {
        if ((NSInteger)out.count >= count) break;
        // Extract track via helper below; entries are LTStatsEntry
        NSString *vid = nil;
        if ([e respondsToSelector:@selector(videoId)]) vid = [e valueForKey:@"videoId"];
        if (!vid) continue;
        // Try library first
        LTTrack *found = nil;
        for (LTTrack *t in self.libraryTracks) {
            if ([t.videoId isEqualToString:vid]) { found = t; break; }
        }
        if (!found) {
            // Search in playlists
            for (LTLocalPlaylist *pl in self.playlists) {
                for (LTTrack *t in pl.tracks) {
                    if ([t.videoId isEqualToString:vid]) { found = t; break; }
                }
                if (found) break;
            }
        }
        if (!found) {
            for (LTTrack *t in self.recentTracks) {
                if ([t.videoId isEqualToString:vid]) { found = t; break; }
            }
        }
        if (found) [out addObject:found];
    }
    return out;
}

- (NSArray *)recentlyPlayedTracks:(NSInteger)count {
    NSArray *recents = [self recentTracks];
    if ((NSInteger)recents.count <= count) return recents;
    return [recents subarrayWithRange:NSMakeRange(0, count)];
}

- (NSArray *)mostTimeListenedTracks:(NSInteger)count {
    NSMutableArray *sorted = [[self mostPlayedTracks] mutableCopy];
    // mostPlayedTracks is sorted by plays; re-sort by seconds via statsEntries
    NSArray *entries = [self statsEntries];
    sorted = [[entries sortedArrayUsingComparator:^NSComparisonResult(LTStatsEntry *a, LTStatsEntry *b) {
        if (a.seconds != b.seconds) return (a.seconds > b.seconds) ? NSOrderedAscending : NSOrderedDescending;
        return [a.title compare:b.title];
    }] mutableCopy];
    NSMutableArray *out = [NSMutableArray array];
    for (id e in sorted) {
        if ((NSInteger)out.count >= count) break;
        NSString *vid = nil;
        if ([e respondsToSelector:@selector(videoId)]) vid = [e valueForKey:@"videoId"];
        if (!vid) continue;
        LTTrack *found = nil;
        for (LTTrack *t in self.libraryTracks) { if ([t.videoId isEqualToString:vid]) { found = t; break; } }
        if (!found) { for (LTLocalPlaylist *pl in self.playlists) { for (LTTrack *t in pl.tracks) { if ([t.videoId isEqualToString:vid]) { found = t; break; } } if (found) break; } }
        if (!found) { for (LTTrack *t in self.recentTracks) { if ([t.videoId isEqualToString:vid]) { found = t; break; } } }
        if (found) [out addObject:found];
    }
    return out;
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

#pragma mark Queue persistence

- (NSString *)downloadQueueFilePath {
    return [[self baseDirectory] stringByAppendingPathComponent:@"downloadQueue.plist"];
}

- (void)loadDownloadQueue {
    NSArray *plist = [NSArray arrayWithContentsOfFile:[self downloadQueueFilePath]];
    if (![plist isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *dict in plist) {
        LTTrack *track = [LTTrack trackWithDictionary:dict];
        if (!track.videoId.length) continue;
        if ([self existingLocalFilePathForVideoId:track.videoId]) continue; // already on disk
        LTDownloadItem *item = [[LTDownloadItem alloc] init];
        item.track = track;
        [self.downloadQueue addObject:item];
    }
    LTLog(@"STORE loaded %d pending downloads", (int)self.downloadQueue.count);
}

- (void)saveDownloadQueue {
    NSMutableArray *plist = [NSMutableArray array];
    for (LTDownloadItem *item in self.downloadQueue) {
        if (!item.track) continue;
        [plist addObject:[item.track dictionaryRepresentation]];
    }
    BOOL ok = [plist writeToFile:[self downloadQueueFilePath] atomically:YES];
    if (!ok) LTLog(@"STORE save downloadQueue failed");
}

- (void)postDownloadQueueChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:LTPlaylistDownloadProgressNotification
                                                        object:self
                                                      userInfo:@{@"status": @"queue",
                                                                 @"index": @(self.downloadIndex),
                                                                 @"total": @(self.downloadTotal),
                                                                 @"videoId": self.downloadingVideoId ?: @""}];
}

- (void)settleItem:(LTDownloadItem *)item failed:(BOOL)failed {
    if (failed) self.downloadFailedCount += 1;
    self.downloadRunCompleted += 1;
    [self releaseItem:item];
}

// Terminates an item without counting it toward run progress (pause/cancel/remove).
- (void)releaseItem:(LTDownloadItem *)item {
    if (!item) return;
    LTDownloadBatch *batch = item.batch;
    item.batch = nil;
    if (batch) {
        batch.remaining -= 1;
        if (batch.remaining <= 0) {
            void (^completion)(void) = batch.completion;
            batch.completion = nil;
            if (completion) completion();
        }
    }
}

#pragma mark Public queue API

- (void)enqueueDownloads:(NSArray *)tracks {
    [self enqueueDownloads:tracks completion:nil];
}

- (void)enqueueDownloads:(NSArray *)tracks completion:(void (^)(void))completion {
    if (!tracks.count) {
        if (completion) completion();
        return;
    }
    NSInteger added = 0;
    LTDownloadBatch *batch = nil;
    if (completion) {
        batch = [[LTDownloadBatch alloc] init];
        batch.completion = completion;
    }
    NSMutableSet *seen = [NSMutableSet set];
    for (LTDownloadItem *existing in self.downloadQueue) {
        if (existing.track.videoId.length) [seen addObject:existing.track.videoId];
    }
    if (self.downloadingVideoId.length) [seen addObject:self.downloadingVideoId];
    for (LTTrack *track in tracks) {
        if (![track isKindOfClass:[LTTrack class]] || !track.videoId.length) continue;
        if ([seen containsObject:track.videoId]) continue;
        [seen addObject:track.videoId];
        LTDownloadItem *item = [[LTDownloadItem alloc] init];
        item.track = track;
        item.batch = batch;
        [self.downloadQueue addObject:item];
        added += 1;
    }
    if (batch) batch.remaining = added;
    if (!added) {
        if (completion) completion();
        return;
    }
    self.downloadTotal = (NSInteger)self.downloadQueue.count;
    [self saveDownloadQueue];
    [self postDownloadQueueChanged];
    LTLog(@"STORE enqueued %d download(s), pending=%d", (int)added, (int)self.downloadQueue.count);
    if (![self isDownloadBusy]) [self startNextDownload];
}

// Legacy entry point: still a "download these now" fire-and-forget. It appends
// like everything else, but drops any pre-existing pending batch first to keep
// the old "this batch runs to completion" behaviour.
- (void)downloadTracks:(NSArray *)tracks completion:(void (^)(void))completion {
    if (!tracks.count) {
        if (completion) completion();
        return;
    }
    if (self.isDownloadBusy) {
        LTLog(@"STORE downloadTracks ignored, engine busy");
        if (completion) completion();
        return;
    }
    // Discard stale pending work so the caller's batch is what runs.
    for (LTDownloadItem *item in [self.downloadQueue copy]) {
        [self releaseItem:item];
    }
    [self.downloadQueue removeAllObjects];
    [self saveDownloadQueue];
    [self enqueueDownloads:tracks completion:completion];
}

- (NSInteger)pendingDownloadCount {
    return (NSInteger)self.downloadQueue.count;
}

- (BOOL)hasPendingDownloads {
    return self.downloadQueue.count > 0;
}

- (NSArray *)pendingDownloadTracks {
    NSMutableArray *tracks = [NSMutableArray array];
    for (LTDownloadItem *item in self.downloadQueue) {
        if (item.track) [tracks addObject:item.track];
    }
    return tracks;
}

- (BOOL)isTrackPendingDownload:(LTTrack *)track {
    if (!track.videoId.length) return NO;
    for (LTDownloadItem *item in self.downloadQueue) {
        if ([item.track.videoId isEqualToString:track.videoId]) return YES;
    }
    return NO;
}

- (void)resumePendingDownloads {
    if (!self.downloadQueue.count) return;
    self.downloadCancelled = NO;
    if (![self isDownloadBusy]) [self startNextDownload];
}

- (void)pausePendingDownloads {
    if (![self isDownloadBusy]) return;
    self.downloadCancelled = YES;
    self.downloadCancelling = NO;
    [self.downloadConnection cancel];
    [self.downloadS6Request cancel];
}

- (void)cancelPendingDownloads {
    self.downloadCancelled = YES;
    self.downloadCancelling = YES;
    if ([self isDownloadBusy]) {
        // The delegate discards the in-flight item; we drop the pending ones now.
        [self.downloadConnection cancel];
        [self.downloadS6Request cancel];
    }
    for (LTDownloadItem *item in [self.downloadQueue copy]) {
        [self releaseItem:item];
    }
    [self.downloadQueue removeAllObjects];
    self.downloadTotal = 0;
    self.downloadIndex = 0;
    self.downloadRunTotal = 0;
    self.downloadRunCompleted = 0;
    [self saveDownloadQueue];
    [self postDownloadQueueChanged];
    if (![self isDownloadBusy]) {
        self.downloadCancelled = NO;
        self.downloadCancelling = NO;
        [self postProgressStatus:@"cancelled"];
    }
}

- (void)removeDownloadsFromQueue:(NSArray *)tracks {
    if (!tracks.count) return;
    NSMutableSet *ids = [NSMutableSet set];
    for (LTTrack *track in tracks) {
        if (track.videoId.length) [ids addObject:track.videoId];
    }
    for (LTDownloadItem *item in [self.downloadQueue copy]) {
        if (![ids containsObject:item.track.videoId]) continue;
        [self.downloadQueue removeObject:item];
        [self releaseItem:item];
    }
    [self saveDownloadQueue];
    [self postDownloadQueueChanged];
}

- (void)clearDownloadFailures {
    self.downloadFailedCount = 0;
    [self postDownloadQueueChanged];
}

#pragma mark Engine

- (void)startNextDownload {
    if (self.downloadCancelled) {
        [self finishDownloads];
        return;
    }
    LTDownloadItem *item = [self.downloadQueue count] ? [self.downloadQueue objectAtIndex:0] : nil;
    if (!item) {
        [self finishDownloads];
        return;
    }
    [self.downloadQueue removeObjectAtIndex:0];
    [self saveDownloadQueue];
    LTTrack *track = item.track;
    self.activeItem = item;
    BOOL freshRun = !self.downloading;
    self.downloading = YES;
    if (freshRun) {
        // A new run: total = this item + everything still queued.
        self.downloadRunTotal = (NSInteger)self.downloadQueue.count + 1;
        self.downloadRunCompleted = 0;
    }
    self.downloadTotal = (NSInteger)self.downloadQueue.count + 1;
    self.downloadIndex = 0;
    if ([self isTrackDownloaded:track]) {
        [self postTrackChanged:track.videoId];
        [self settleItem:item failed:NO];
        [self postProgressStatus:@"skipped"];
        [self startNextDownload];
        return;
    }
    self.downloadingVideoId = track.videoId;
    self.downloadingTrack = track;
    [self postProgressStatus:@"fetching"];
    __unsafe_unretained LTPlaylistStore *weakSelf = self;
    [[LTYouTubeClient sharedClient] streamURLForVideo:track.videoId completion:^(NSString *streamURL, BOOL muxedStream, NSInteger audioBitrateKbps, NSError *error) {
        LTPlaylistStore *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error || !streamURL.length) {
            LTLog(@"STORE DL stream error %@ for %@", error, track.videoId);
            strongSelf.downloadingVideoId = nil;
            strongSelf.downloadingTrack = nil;
            strongSelf.downloadIndex += 1;
            [strongSelf settleItem:strongSelf.activeItem failed:YES];
            strongSelf.activeItem = nil;
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
    self.downloadData = [NSMutableData data];
    self.downloadHTTPStatus = 0;

    // iOS 6.x system HTTPS often cannot negotiate with googlevideo CDNs; use
    // mbedTLS there for compatibility.
    if ([[[UIDevice currentDevice] systemVersion] floatValue] < 7.0f) {
        NSURL *url = [NSURL URLWithString:urlString];
        S6HTTPRequest *req = [[S6HTTPRequest alloc] initWithMethod:@"GET" URL:url];
        req.headers = @{ @"Range": @"bytes=0-",
                         @"User-Agent": LTBrowserUserAgent ?: @"" };
        req.connectTimeout = 30;
        req.readTimeout = 120;
        req.noCompression = YES;
        __unsafe_unretained LTPlaylistStore *weakSelf = self;
        __unsafe_unretained S6HTTPRequest *weakReq = req;
        req.onHeaders = ^(NSInteger status, NSDictionary *headers) {
            dispatch_async(dispatch_get_main_queue(), ^{
                LTPlaylistStore *strongSelf = weakSelf;
                if (!strongSelf || strongSelf.downloadS6Request != weakReq) return;
                strongSelf.downloadHTTPStatus = status;
                [strongSelf.downloadData setLength:0];
                LTLog(@"STORE DL_RESPONSE status=%d (mbedTLS)", (int)status);
            });
        };
        req.onData = ^(NSData *chunk) {
            if (!chunk.length) return;
            NSData *chunkCopy = [chunk copy];
            dispatch_async(dispatch_get_main_queue(), ^{
                LTPlaylistStore *strongSelf = weakSelf;
                if (!strongSelf || strongSelf.downloadS6Request != weakReq) return;
                [strongSelf.downloadData appendData:chunkCopy];
            });
        };
        req.onComplete = ^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                LTPlaylistStore *strongSelf = weakSelf;
                if (!strongSelf) return;
                if (strongSelf.downloadS6Request != weakReq) return;
                strongSelf.downloadS6Request = nil;
                if (error) {
                    [strongSelf handleDownloadDidFailWithError:error];
                } else {
                    [strongSelf handleDownloadDidFinishLoading];
                }
            });
        };
        self.downloadS6Request = req;
        LTLog(@"STORE DL start %@ (mbedTLS)", videoId);
        [req start];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]
                                                            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                        timeoutInterval:120.0];
    [request setValue:@"bytes=0-" forHTTPHeaderField:@"Range"];
    [request setValue:LTBrowserUserAgent forHTTPHeaderField:@"User-Agent"];
    self.downloadConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    LTLog(@"STORE DL start %@", videoId);
}

- (void)finishDownloads {
    self.downloading = NO;
    self.downloadConnection = nil;
    self.downloadS6Request = nil;
    self.downloadData = nil;
    self.downloadingVideoId = nil;
    self.downloadingTrack = nil;
    self.activeItem = nil;
    [self saveDownloadQueue];
    [self postProgressStatus: self.downloadQueue.count ? @"paused" : @"finished"];
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
    __unsafe_unretained LTPlaylistStore *weakSelf = self;
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
    __unsafe_unretained LTPlaylistStore *weakSelf = self;
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
        // Run-level progress: how many items of the whole queue are done.
        @"index": @(self.downloadRunCompleted),
        @"total": @(self.downloadRunTotal),
        @"videoId": self.downloadingVideoId ?: @"",
        @"pending": @(self.downloadQueue.count),
        @"failed": @(self.downloadFailedCount),
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

- (void)handleDownloadDidFailWithError:(NSError *)error {
    LTLog(@"STORE DL_ERROR %@ for %@", error, self.downloadingVideoId);
    NSString *videoId = self.downloadingVideoId;
    [self postTrackChanged:videoId];
    self.downloadingVideoId = nil;
    self.downloadingTrack = nil;
    self.downloadIndex += 1;
    if (self.downloadCancelled) {
        LTDownloadItem *item = self.activeItem;
        if (item && !self.downloadCancelling) {
            // Paused (not cancelled): put the item back at the head to resume.
            [self.downloadQueue insertObject:item atIndex:0];
            [self saveDownloadQueue];
        }
        [self releaseItem:item];
        self.activeItem = nil;
        BOOL wasCancelling = self.downloadCancelling;
        self.downloadCancelled = NO;
        self.downloadCancelling = NO;
        self.downloading = NO;
        self.downloadConnection = nil;
        self.downloadS6Request = nil;
        self.downloadData = nil;
        if (wasCancelling) {
            self.downloadTotal = 0;
            self.downloadIndex = 0;
            [self postProgressStatus:@"cancelled"];
        } else {
            [self postProgressStatus:@"paused"];
        }
        [self postDownloadQueueChanged];
        return;
    }
    [self settleItem:self.activeItem failed:YES];
    self.activeItem = nil;
    [self postProgressStatus:@"error"];
    [self startNextDownload];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    (void)connection;
    [self handleDownloadDidFailWithError:error];
}

- (void)handleDownloadDidFinishLoading {
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
    [self settleItem:self.activeItem failed:!ok];
    self.activeItem = nil;
    [self postProgressStatus: ok ? @"downloaded" : @"error"];
    [self startNextDownload];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    (void)connection;
    [self handleDownloadDidFinishLoading];
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
            @"updatedAt": [[NSDate date] description],
        }];
    }
    return exportArray;
}

// Union-merge incoming playlists by id; tracks merge by videoId.
- (NSInteger)mergeSyncArray:(NSArray *)incomingArray {
    if (![incomingArray isKindOfClass:[NSArray class]]) return 0;
    NSInteger merged = 0;
    for (NSDictionary *playlistDict in incomingArray) {
        NSString *playlistId = [playlistDict objectForKey:@"id"];
        NSString *name = [playlistDict objectForKey:@"name"];
        if (!playlistId.length || !name.length) continue;
        LTLocalPlaylist *existing = nil;
        for (LTLocalPlaylist *p in [_playlists copy]) {
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
        NSArray *songs = [playlistDict objectForKey:@"songs"];
        if ([songs isKindOfClass:[NSArray class]]) {
            for (NSDictionary *songDict in songs) {
                NSString *videoId = [songDict objectForKey:@"videoId"];
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
    NSData *data = [S6JSON dataWithObject:[self syncArrayRepresentation] error:&writeError];
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
    NSArray *importArray = [S6JSON objectWithData:data error:&parseError];
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

- (NSArray *)stationsSyncArray {
    NSMutableArray *result = [NSMutableArray array];
    for (LTStation *station in self.stations) {
        [result addObject:[station dictionaryRepresentation]];
    }
    return result;
}

- (NSDictionary *)statsSyncDict {
    NSDictionary *dict = [self statsFileDict];
    NSDictionary *tracks = [dict objectForKey:@"tracks"];
    if (![tracks isKindOfClass:[NSDictionary class]]) tracks = [NSDictionary dictionary];
    // Only ship this phone's OWN listening stats. Received (synced) stats live
    // in a separate per-device ledger and must not be re-exported.
    NSMutableDictionary *trimmedTracks = [NSMutableDictionary dictionary];
    for (NSString *videoId in tracks) {
        NSDictionary *entry = [tracks objectForKey:videoId];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *trimmed = [NSMutableDictionary dictionary];
        [trimmed setObject:[entry objectForKey:@"title"] ?: @"" forKey:@"title"];
        [trimmed setObject:[entry objectForKey:@"artist"] ?: @"" forKey:@"artist"];
        [trimmed setObject:[entry objectForKey:@"album"] ?: @"" forKey:@"album"];
        [trimmed setObject:[entry objectForKey:@"thumbnailURL"] ?: @"" forKey:@"thumbnailURL"];
        [trimmed setObject:@([[entry objectForKey:@"plays"] integerValue]) forKey:@"plays"];
        [trimmed setObject:@([[entry objectForKey:@"seconds"] doubleValue]) forKey:@"seconds"];
        [trimmedTracks setObject:trimmed forKey:videoId];
    }
    return @{@"tracks": trimmedTracks};
}

- (NSDictionary *)syncPayload {
    return @{
        @"version": @1,
        @"deviceId": [self syncDeviceId],
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"playlists": [self syncArrayRepresentation],
        @"stations": [self stationsSyncArray],
        @"library": [self librarySyncArray],
        @"recents": [self recentsSyncArray],
        @"stats": [self statsSyncDict],
        @"listenedIds": [self listenedSongIDs],
    };
}

- (NSString *)syncDeviceId {
    NSString *deviceId = [[NSUserDefaults standardUserDefaults] stringForKey:@"LTSyncDeviceId"];
    if (!deviceId.length) {
        // identifierForVendor is iOS 6+; on iOS 4/5 fall back to a persisted
        // random UUID so the sync identity stays stable across launches.
        UIDevice *device = [UIDevice currentDevice];
        if ([device respondsToSelector:@selector(identifierForVendor)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id vendor = [device performSelector:@selector(identifierForVendor)];
#pragma clang diagnostic pop
            if ([vendor respondsToSelector:@selector(UUIDString)]) deviceId = [vendor UUIDString];
        }
        if (!deviceId.length) deviceId = LTGenerateUUIDString();
        [[NSUserDefaults standardUserDefaults] setObject:deviceId forKey:@"LTSyncDeviceId"];
    }
    return deviceId;
}

- (void)mergeSyncPayload:(NSDictionary *)payload {
    if (![payload isKindOfClass:[NSDictionary class]]) return;
    BOOL changed = NO;

    NSArray *playlists = [payload objectForKey:@"playlists"];
    if ([playlists isKindOfClass:[NSArray class]]) {
        NSInteger m = [self mergeSyncArray:playlists];
        if (m > 0) changed = YES;
    }

    NSArray *stations = [payload objectForKey:@"stations"];
    if ([stations isKindOfClass:[NSArray class]]) {
        for (NSDictionary *dict in stations) {
            if (![dict isKindOfClass:[NSDictionary class]]) continue;
            LTStation *incoming = [LTStation stationWithDictionary:dict];
            if (!incoming.identifier.length) continue;
            BOOL exists = NO;
            for (LTStation *local in self.stations) {
                if ([local.identifier isEqualToString:incoming.identifier]) { exists = YES; break; }
            }
            if (!exists) {
                [_stations addObject:incoming];
                changed = YES;
            }
        }
        if (changed) [self saveStations];
    }

    NSArray *library = [payload objectForKey:@"library"];
    if ([library isKindOfClass:[NSArray class]]) {
        for (NSDictionary *dict in library) {
            if (![dict isKindOfClass:[NSDictionary class]]) continue;
            LTTrack *track = [LTTrack trackWithDictionary:dict];
            if (!track.videoId.length) continue;
            [self addTrackToLibrary:track];
            changed = YES; // addTrackToLibrary is itself idempotent/updating
        }
    }

    NSArray *recents = [payload objectForKey:@"recents"];
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
        _recentsCache = nil;
        changed = YES;
    }

    NSDictionary *stats = [payload objectForKey:@"stats"];
    if ([stats isKindOfClass:[NSDictionary class]]) {
        NSDictionary *incomingTracks = [stats objectForKey:@"tracks"];
        if ([incomingTracks isKindOfClass:[NSDictionary class]]) {
            NSString *fromDevice = [payload objectForKey:@"deviceId"];
            BOOL hasPeerId = ([fromDevice isKindOfClass:[NSString class]] && fromDevice.length);
            NSMutableDictionary *dict = [self statsFileDict];
            if (hasPeerId) {
                // Echo guard: if the payload claims to be from THIS device, it is
                // our own self-sync (see LTP2PSync self-discovery) — never create
                // a self-referential ledger entry, it would inflate the totals.
                if (![fromDevice isEqualToString:[self syncDeviceId]]) {
                    // Ledger merge: save a snapshot of this peer's OWN stats keyed by
                    // their device id. Combined totals = our own + each peer's own, so
                    // re-syncing the same phones never double-counts previous syncs.
                    NSMutableDictionary *received = [dict objectForKey:@"received"];
                    if (![received isKindOfClass:[NSMutableDictionary class]]) {
                        received = [NSMutableDictionary dictionary];
                    }
                    NSMutableDictionary *peerLedger = [NSMutableDictionary dictionary];
                    for (NSString *videoId in incomingTracks) {
                        NSDictionary *incoming = [incomingTracks objectForKey:videoId];
                        if (![incoming isKindOfClass:[NSDictionary class]]) continue;
                        [peerLedger setObject:[NSMutableDictionary dictionaryWithDictionary:incoming] forKey:videoId];
                    }
                    [received setObject:peerLedger forKey:fromDevice];
                    [dict setObject:received forKey:@"received"];
                    [self writeStatsFileDict:dict];
                    changed = YES;
                }
            } else {
                // Legacy merge without a peer id: sum into our own stats so no
                // history is lost.
                for (NSString *videoId in incomingTracks) {
                    NSDictionary *incoming = [incomingTracks objectForKey:videoId];
                    if (![incoming isKindOfClass:[NSDictionary class]]) continue;
                    NSMutableDictionary *entry = [self statsEntryForVideoId:videoId inDict:dict];
                    NSInteger inPlays = [[incoming objectForKey:@"plays"] integerValue];
                    NSInteger localPlays = [[entry objectForKey:@"plays"] integerValue];
                    [entry setObject:@(localPlays + inPlays) forKey:@"plays"];
                    double inSeconds = [[incoming objectForKey:@"seconds"] doubleValue];
                    double localSeconds = [[entry objectForKey:@"seconds"] doubleValue];
                    [entry setObject:@(localSeconds + inSeconds) forKey:@"seconds"];
                    if (![[entry objectForKey:@"title"] length]) [entry setObject:[incoming objectForKey:@"title"] ?: @"" forKey:@"title"];
                    if (![[entry objectForKey:@"artist"] length]) [entry setObject:[incoming objectForKey:@"artist"] ?: @"" forKey:@"artist"];
                    if (![[entry objectForKey:@"album"] length]) [entry setObject:[incoming objectForKey:@"album"] ?: @"" forKey:@"album"];
                    if (![[entry objectForKey:@"thumbnailURL"] length]) [entry setObject:[incoming objectForKey:@"thumbnailURL"] ?: @"" forKey:@"thumbnailURL"];
                }
                [self writeStatsFileDict:dict];
                changed = YES;
            }
        }
    }

    NSArray *listenedIds = [payload objectForKey:@"listenedIds"];
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
