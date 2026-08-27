#import <Foundation/Foundation.h>
#import "LTModel.h"

extern NSString *const LTPlaylistsDidChangeNotification;
extern NSString *const LTPlaylistTrackDidChangeNotification;
extern NSString *const LTPlaylistDownloadProgressNotification;
extern NSString *const LTRecentsDidChangeNotification;

@interface LTPlaylistStore : NSObject

+ (instancetype)sharedStore;

@property (nonatomic, readonly) NSArray *playlists;
@property (nonatomic, readonly) NSArray *recentTracks;

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
- (NSInteger)offlineFileCount;

- (NSString *)localFilePathForVideoId:(NSString *)videoId;
- (NSString *)existingLocalFilePathForVideoId:(NSString *)videoId;
- (BOOL)isTrackDownloaded:(LTTrack *)track;
- (BOOL)isDownloading;

- (void)downloadTracks:(NSArray *)tracks completion:(void (^)(void))completion;

- (NSInteger)offlineTrackCount;
- (void)refreshOfflineMetadataWithProgress:(void (^)(NSInteger done, NSInteger total))progress
                            completion:(void (^)(NSInteger updated, NSInteger failed))completion;

- (BOOL)exportPlaylistsToJSONFile:(NSString *)filePath error:(NSError **)error;
- (BOOL)importPlaylistsFromJSONFile:(NSString *)filePath error:(NSError **)error;

- (NSArray *)syncArrayRepresentation;
- (NSInteger)mergeSyncArray:(NSArray *)incomingArray;

@end
