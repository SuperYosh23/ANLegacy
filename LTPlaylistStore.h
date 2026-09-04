#import <Foundation/Foundation.h>
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
@property (nonatomic, readonly) NSArray *recentTracks;
@property (nonatomic, readonly) NSArray *libraryTracks;

- (NSString *)baseDirectory;
- (NSString *)audioDirectory;
- (NSString *)artDirectory;

- (LTLocalPlaylist *)createPlaylistWithName:(NSString *)name;
- (void)deletePlaylist:(LTLocalPlaylist *)playlist;
- (void)renamePlaylist:(LTLocalPlaylist *)playlist name:(NSString *)name;
- (void)setCoverImage:(UIImage *)image forPlaylist:(LTLocalPlaylist *)playlist;
- (void)addTrack:(LTTrack *)track toPlaylist:(LTLocalPlaylist *)playlist;
- (void)removeTrackAtIndex:(NSInteger)index fromPlaylist:(LTLocalPlaylist *)playlist;

- (void)recordRecentTrack:(LTTrack *)track;
- (NSInteger)listenedSongsCount;
- (NSInteger)offlineFileCount;

- (NSArray *)searchHistory;
- (void)recordSearchTerm:(NSString *)term;
- (void)clearSearchHistory;

- (void)recordTrackPlay:(LTTrack *)track;
- (void)recordListenedSeconds:(NSTimeInterval)seconds forTrack:(LTTrack *)track;
- (void)clearListeningStats;
- (NSArray *)mostPlayedTracks;
- (NSArray *)topArtists;
- (NSTimeInterval)totalListeningTime;
- (NSInteger)totalPlayCount;

- (NSString *)localFilePathForVideoId:(NSString *)videoId;
- (NSString *)existingLocalFilePathForVideoId:(NSString *)videoId;
- (BOOL)isTrackDownloaded:(LTTrack *)track;
- (BOOL)isTrackDownloading:(LTTrack *)track;
- (BOOL)isDownloading;

- (void)downloadTracks:(NSArray *)tracks completion:(void (^)(void))completion;
- (void)removeDownloadsForTracks:(NSArray *)tracks;
- (NSArray *)downloadedTracks;
- (void)addTrackToLibrary:(LTTrack *)track;

- (NSInteger)offlineTrackCount;
- (void)refreshOfflineMetadataWithProgress:(void (^)(NSInteger done, NSInteger total))progress
                            completion:(void (^)(NSInteger updated, NSInteger failed))completion;

- (void)resolveThumbnailForTrack:(LTTrack *)track
                      completion:(void (^)(NSString *thumbnailURL))completion;

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
