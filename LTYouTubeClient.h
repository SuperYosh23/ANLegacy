#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const LTAPIKey;
extern NSString *const LTBrowserUserAgent;

// Forward declaration: artworkURLsForTrack: takes an LTTrack*, and this header
// deliberately does not import LTModel.h (callers import it). Without this the
// compiler sees an unknown type where the method signature should be.
@class LTTrack;

@interface LTYouTubeClient : NSObject

+ (instancetype)sharedClient;

@property (nonatomic, copy) NSString *visitorData;

// Populated when a stream format is successfully selected by
// streamURLForVideo:completion:. Keys: videoId, clientName, itag,
// mimeType, bitrate (bps), audioSampleRate, muxed.
@property (nonatomic, copy) NSDictionary *lastFormatInfo;

- (void)fetchRadioForTrack:(LTTrack *)track completion:(void (^)(NSArray *tracks, NSError *error))completion;
- (void)fetchRadioForArtist:(NSString *)artist completion:(void (^)(NSArray *tracks, NSError *error))completion;

- (void)searchWithQuery:(NSString *)query type:(NSString *)type
             completion:(void (^)(NSArray *items, NSError *error))completion;

- (void)searchVideosWithQuery:(NSString *)query
                   completion:(void (^)(NSArray *tracks, NSError *error))completion;

- (void)browseAlbum:(NSString *)browseId
         completion:(void (^)(NSDictionary *info, NSArray *tracks, NSError *error))completion;

- (void)browsePlaylist:(NSString *)browseId
            completion:(void (^)(NSDictionary *info, NSArray *tracks, NSError *error))completion;

// `topSongs` is the "Top songs" shelf as YouTube emits it; `allSongs` is every
// song on the page, de-duplicated across shelves and sorted by play count
// descending, which is what a "show all" list wants.
- (void)browseArtist:(NSString *)browseId
          completion:(void (^)(NSDictionary *info, NSArray *topSongs, NSArray *allSongs, NSArray *albums, NSError *error))completion
          avatarURL:(void (^)(NSString *avatarURL))avatarBlock;

- (void)channelAvatarURLForBrowseId:(NSString *)browseId
                         completion:(void (^)(NSString *avatarURL))completion;

- (void)resolveArtistAvatarForName:(NSString *)name
                        completion:(void (^)(NSString *avatarURL))completion;

- (void)resolveArtistBrowseId:(NSString *)name
                   completion:(void (^)(NSString *browseId))completion;

- (void)fetchTrendingSongsWithCompletion:(void (^)(NSArray *tracks, NSError *error))completion;

- (void)streamURLForVideo:(NSString *)videoId
               completion:(void (^)(NSString *streamURL, BOOL muxedStream, NSInteger audioBitrateKbps, NSError *error))completion;

- (void)trackMetadataForVideoId:(NSString *)videoId
                     completion:(void (^)(NSString *title, NSString *artist, NSTimeInterval duration, NSString *thumbnailURL, NSError *error))completion;

- (void)loadImageWithURL:(NSString *)urlString
              completion:(void (^)(UIImage *image))completion;

// Load artwork for a table row, safely under cell reuse.
//
// -loadImageWithURL: on its own is unsafe to point at a cell: it answers
// asynchronously, and by the time it does the cell may have been recycled onto
// a different row. Writing then puts one row's art on another row and leaves
// the intended row blank, which is why covers used to appear and vanish
// seemingly at random on lists that scroll. This remembers what the cell was
// asked to show and drops the image if that has changed by the time it lands.
//
// Passing a nil or empty URL still clears the cell, so callers can use it
// unconditionally after resetting the cell.
- (void)loadArtworkURL:(NSString *)urlString intoCell:(UITableViewCell *)cell;

- (void)fetchLyricsForVideo:(NSString *)videoId
                 completion:(void (^)(NSString *lyricsText, NSError *error))completion;

// Fetches YouTube Music lyrics for a video. Yields either timestamped lines
// (NSArray of @{"text", "start", "end"} in ms, "hasTimestamps"=YES) or a raw
// plain-text lyric blob ({"lyrics":..., "hasTimestamps"=NO}). "source" carries
// the attribution string ("Source: LyricFind"). Falls back gracefully.
- (void)fetchTimedLyricsForVideoId:(NSString *)videoId
                        completion:(void (^)(NSDictionary *result, NSError *error))completion;

// Descriptive facts about a video for the player's General page. Yields a
// dictionary that may contain title, uploader, channelId, viewCount, likeCount,
// avatarURL and durationSeconds; absent keys mean the field was not returned.
- (void)fetchVideoGeneralInfoForVideoId:(NSString *)videoId
                              completion:(void (^)(NSDictionary *info, NSError *error))completion;

// Widens a thumbnail URL to the largest size that URL format supports. For
// i.ytimg.com this is a no-op (those URLs name their size); use
// artworkURLsForTrack: to get a real size ladder.
- (NSString *)highResThumbnailURL:(NSString *)urlString;

// The artwork already cached on disk for a URL, if there is any. Returns nil
// when nothing has been cached for it, so a caller can decide what to show
// instead.
- (UIImage *)cachedArtworkForURL:(NSString *)urlString;

// Loads artwork, walking the candidates above until one is large enough to be
// real cover art. Falls back to nil only if every candidate fails.
- (void)loadArtworkFromCandidates:(NSArray *)urls
                              index:(NSUInteger)index
                        completion:(void (^)(UIImage *image))completion;

// Candidate artwork URLs for a track, sharpest first, with sensible fallbacks.
// A YouTube "maxresdefault" request that does not exist answers HTTP 404 with a
// valid 120x90 placeholder, so callers must treat a too-small image as a miss
// rather than success -- loadArtworkFromCandidates:index:completion: does that.
- (NSArray *)artworkURLsForTrack:(LTTrack *)track;

- (NSString *)channelAvatarURL:(NSString *)urlString size:(NSInteger)size;

@end
