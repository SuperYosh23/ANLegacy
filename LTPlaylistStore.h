#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LTModel.h"

extern NSString *const LTPlaylistsDidChangeNotification;
extern NSString *const LTPlaylistTrackDidChangeNotification;
extern NSString *const LTPlaylistDownloadProgressNotification;
extern NSString *const LTRecentsDidChangeNotification;

@interface LTStatsEntry : NSObject
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *thumbnailURL;
@property (nonatomic, assign) NSInteger plays;
@property (nonatomic, assign) NSTimeInterval seconds;
@end

@interface LTPlaylistStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, readonly) NSArray *playlists;
@property (nonatomic, readonly) NSArray *stations;
@property (nonatomic, readonly) NSArray *recentTracks;
@property (nonatomic, readonly) NSArray *libraryTracks;

- (NSString *)baseDirectory;
- (NSString *)audioDirectory;
- (NSString *)artDirectory;
- (NSString *)lyricsDirectory;

// --- Lyrics cache -------------------------------------------------------------
// Lyrics are stored one JSON file per video id so they survive relaunches and
// work with no network at all. A "no lyrics for this song" answer is cached too
// (as an empty dictionary), otherwise an offline track would re-attempt a fetch
// on every single play and always fail.

// Returns the cached payload for videoId, or nil when nothing is cached yet.
- (NSDictionary *)cachedLyricsForVideoId:(NSString *)videoId;

// Stores a fetch result. Pass nil or an empty dictionary to record "none".
- (void)cacheLyrics:(NSDictionary *)payload forVideoId:(NSString *)videoId;

// Removes all cached lyrics.
- (void)clearLyricsCache;

// Bytes used by the lyrics cache, for the storage screen.
- (unsigned long long)lyricsCacheSize;

- (void)saveStations;
- (LTStation *)createStationWithName:(NSString *)name seeds:(NSArray *)seeds;
- (void)deleteStation:(LTStation *)station;
- (void)renameStation:(LTStation *)station name:(NSString *)name;
- (void)setCoverImage:(UIImage *)image forStation:(LTStation *)station;
- (LTLocalPlaylist *)createPlaylistWithName:(NSString *)name;
- (void)deletePlaylist:(LTLocalPlaylist *)playlist;
- (void)renamePlaylist:(LTLocalPlaylist *)playlist name:(NSString *)name;
- (void)setCoverImage:(UIImage *)image forPlaylist:(LTLocalPlaylist *)playlist;

// Artwork for a playlist row in a list.
//
// A playlist whose cover was set renders synchronously from disk. One without
// falls back to the first track's thumbnail, which needs a fetch - so on a
// network where that fetch is slow or blocked the row showed nothing at all,
// and re-fetched on every list rebuild. Once the fallback has been fetched it
// is stored as the playlist's cover, after which the row renders locally and
// never needs the network again.
//
// Returns YES when the cell was filled synchronously (a cover was already on
// disk), NO when a load was started.
+ (BOOL)providePlaylistArtwork:(LTLocalPlaylist *)playlist toCell:(UITableViewCell *)cell;

// Stores a cover derived from a track's thumbnail, as opposed to one the
// listener picked.
//
// Deliberately does not post a change notification: it is called from a table's
// cell rendering, and a notification there would reload that same table while
// it is mid-layout.
- (void)cacheDerivedCoverImage:(UIImage *)image forPlaylist:(LTLocalPlaylist *)playlist;
- (void)addTrack:(LTTrack *)track toPlaylist:(LTLocalPlaylist *)playlist;
- (void)removeTrackAtIndex:(NSInteger)index fromPlaylist:(LTLocalPlaylist *)playlist;

// --- Duplicate-name guard ------------------------------------------------------
// -addTrack:toPlaylist: silently drops a track that is already in the playlist by
// video id. That is not what "a duplicate" means to a listener though: the
// common case is two genuinely different recordings that share a title (a live
// and a studio cut, the same song from two uploads). Those both get added, and
// the playlist ends up full of identical-looking rows. So before adding, check
// titles and ask.

// Subset of `tracks` whose title case-insensitively matches a track already in
// `playlist`. Empty when every title is new.
+ (NSArray *)duplicateTitledTracks:(NSArray *)tracks inPlaylist:(LTLocalPlaylist *)playlist;

// The one entry point every "add to playlist" flow should use.
//
// Tracks whose title is new to the playlist are added immediately. Each track
// whose title already appears in the playlist then gets its own confirmation —
// one dialog per song, offering "Don't Add" or "Add Anyway" — rather than a
// single dialog about the whole batch, so each decision is about one song and
// "Don't Add" skips only that song.
//
// `completion` runs with the number added once the last dialog has been
// answered, so callers should not expect it before then. It is optional. Adding
// is skipped entirely if `tracks` is empty.
+ (void)addTracks:(NSArray *)tracks
      toPlaylist:(LTLocalPlaylist *)playlist
confirmingFrom:(UIViewController *)presenter
      completion:(void (^)(NSInteger addedCount))completion;

// Single-track convenience wrapper around the above.
+ (void)addTrack:(LTTrack *)track
     toPlaylist:(LTLocalPlaylist *)playlist
confirmingFrom:(UIViewController *)presenter
      completion:(void (^)(BOOL added))completion;

// --- Delete confirmation --------------------------------------------------------
// Deleting a playlist is immediate and there is no undo: the track list is gone
// and so is the playlist's identity, cover and name. So the swipe-to-delete
// gesture asks first, from whichever controller owns the row.
//
// `completion` reports whether the playlist was actually deleted, so callers
// should do their table bookkeeping (removing the row) from there rather than
// optimistically before the prompt is answered.
+ (void)confirmDeletePlaylist:(LTLocalPlaylist *)playlist
                  presenting:(UIViewController *)presenter
                  completion:(void (^)(BOOL deleted))completion;

- (void)recordRecentTrack:(LTTrack *)track;
- (NSInteger)listenedSongsCount;
- (NSInteger)offlineFileCount;

- (NSArray *)searchHistory;
- (void)recordSearchTerm:(NSString *)term;
- (void)clearSearchHistory;

- (void)recordTrackPlay:(LTTrack *)track;
- (void)recordListenedSeconds:(NSTimeInterval)seconds forTrack:(LTTrack *)track;
- (void)clearListeningStats;
- (void)clearRecents;

- (NSArray *)topPlayedTracks:(NSInteger)count;
- (NSArray *)recentlyPlayedTracks:(NSInteger)count;
- (NSArray *)mostTimeListenedTracks:(NSInteger)count;

// Writes any pending listening-stats changes to disk now. Writes are otherwise
// debounced by a couple of seconds; call this when the app is about to lose the
// foreground so a backgrounded or killed app cannot lose the last few seconds.
- (void)flushListeningStats;
- (NSArray *)mostPlayedTracks;
- (NSArray *)topArtists;
- (NSTimeInterval)totalListeningTime;
- (NSInteger)totalPlayCount;

- (NSString *)localFilePathForVideoId:(NSString *)videoId;
- (NSString *)existingLocalFilePathForVideoId:(NSString *)videoId;
- (BOOL)isTrackDownloaded:(LTTrack *)track;
- (BOOL)isTrackDownloading:(LTTrack *)track;
- (BOOL)isDownloading;

// Appends to the persistent download queue (nothing is clobbered, requests are
// never dropped) and starts pumping if the engine is idle. `completion` runs on
// the main thread once every track passed in here has been processed.
- (void)enqueueDownloads:(NSArray *)tracks completion:(void (^)(void))completion;
// Fire-and-forget variant for menus/rows.
- (void)enqueueDownloads:(NSArray *)tracks;

- (void)downloadTracks:(NSArray *)tracks completion:(void (^)(void))completion;
- (void)removeDownloadsForTracks:(NSArray *)tracks;
- (NSArray *)downloadedTracks;
- (void)addTrackToLibrary:(LTTrack *)track;

// Drops a track from the library, by video id.
//
// The library has to be able to shrink. It gains entries from downloads, from
// adding a song to a playlist, and from peer sync, so anything that was ever in
// a playlist stayed there forever after being removed from it - there was no way
// back out. Only the library entry goes; the audio file, any playlist
// membership and listening stats are untouched.
- (void)removeTrackFromLibrary:(LTTrack *)track;

- (NSInteger)offlineTrackCount;
- (NSInteger)pendingDownloadCount;
- (BOOL)hasPendingDownloads;
- (NSArray *)pendingDownloadTracks;
- (BOOL)isTrackPendingDownload:(LTTrack *)track;
- (void)resumePendingDownloads;
- (void)pausePendingDownloads;
- (void)cancelPendingDownloads;
- (void)removeDownloadsFromQueue:(NSArray *)tracks;
- (void)clearDownloadFailures;
- (void)refreshOfflineMetadataWithProgress:(void (^)(NSInteger done, NSInteger total))progress
                            completion:(void (^)(NSInteger updated, NSInteger failed))completion;

- (void)resolveThumbnailForTrack:(LTTrack *)track
                      completion:(void (^)(NSString *thumbnailURL))completion;

- (NSString *)artistAvatarURLForName:(NSString *)name;
- (void)setArtistAvatarURL:(NSString *)url forName:(NSString *)name;

- (void)recordBitrateKbps:(NSInteger)kbps forVideoId:(NSString *)videoId;
- (NSInteger)bitrateKbpsForVideoId:(NSString *)videoId;

- (BOOL)exportPlaylistsToJSONFile:(NSString *)filePath error:(NSError **)error;
- (BOOL)importPlaylistsFromJSONFile:(NSString *)filePath error:(NSError **)error;

- (NSArray *)syncArrayRepresentation;
- (NSInteger)mergeSyncArray:(NSArray *)incomingArray;

// Full-state sync used for phone-to-phone peer sync: playlists + library +
// recents + listening stats + known-listened song ids.
- (NSDictionary *)syncPayload;
- (void)mergeSyncPayload:(NSDictionary *)payload;

// Sub-representations composing the full payload.
- (NSArray *)librarySyncArray;
- (NSArray *)recentsSyncArray;
- (NSDictionary *)statsSyncDict;

@end
