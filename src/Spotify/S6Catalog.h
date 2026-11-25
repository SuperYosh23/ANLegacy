#import <Foundation/Foundation.h>

@class S6Album, S6Artist, S6Playlist, S6Show, S6Track;

// A titled row of things (a shelf of Home, a browse page)
@interface S6Shelf : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray *items;          // S6Album, S6Playlist, S6Artist, S6Show, S6Track (episodes)
@end

// What an artist's page shows
@interface S6ArtistPage : NSObject
@property (nonatomic, strong) S6Artist *artist;
@property (nonatomic, copy) NSArray *topTracks;      // S6Track
@property (nonatomic, copy) NSArray *albums;         // S6Album
@property (nonatomic, copy) NSArray *singles;
@property (nonatomic, copy) NSArray *compilations;
@property (nonatomic, copy) NSArray *appearsOn;
@property (nonatomic, copy) NSArray *related;        // S6Artist ("Fans also like")
@property (nonatomic, copy) NSArray *playlists;      // S6Playlist ("Featuring")
@end

@interface S6SearchResults : NSObject
@property (nonatomic, strong) id topResult;
@property (nonatomic, copy) NSArray *tracks;
@property (nonatomic, copy) NSArray *artists;
@property (nonatomic, copy) NSArray *albums;
@property (nonatomic, copy) NSArray *playlists;
@property (nonatomic, copy) NSArray *shows;
@property (nonatomic, copy) NSArray *episodes;
@property (nonatomic, readonly) BOOL empty;
@end

// Spotify's catalogue and the user's library through the GraphQL API the official clients use (S6Pathfinder).
// Completions run on the main thread.
@interface S6Catalog : NSObject

+ (void)home:(void (^)(NSString *greeting, NSArray *sections, NSError *error))completion;
+ (void)search:(NSString *)query completion:(void (^)(S6SearchResults *results, NSError *error))completion;
+ (void)browseCategories:(void (^)(NSArray *categories, NSError *error))completion;   // NSDictionary {title, uri, image, color}
+ (void)browsePage:(NSString *)uri completion:(void (^)(NSString *title, NSArray *sections, NSError *error))completion;

+ (void)album:(NSString *)uri completion:(void (^)(S6Album *album, NSError *error))completion;    // with its tracks
+ (void)artist:(NSString *)uri completion:(void (^)(S6ArtistPage *page, NSError *error))completion;
+ (void)playlist:(NSString *)uri offset:(NSInteger)offset limit:(NSInteger)limit
      completion:(void (^)(S6Playlist *playlist, NSArray *tracks, NSInteger total, NSError *error))completion;
+ (void)likedSongsOffset:(NSInteger)offset limit:(NSInteger)limit
              completion:(void (^)(NSArray *tracks, NSInteger total, NSError *error))completion;
+ (void)show:(NSString *)uri completion:(void (^)(S6Show *show, NSError *error))completion;
+ (void)showEpisodes:(NSString *)uri offset:(NSInteger)offset limit:(NSInteger)limit
          completion:(void (^)(NSArray *episodes, NSInteger total, NSError *error))completion;
+ (void)tracksForURIs:(NSArray *)uris completion:(void (^)(NSArray *tracks, NSError *error))completion;

// The library: filter "Playlists", "Albums", "Artists" or "Podcasts" (nil: everything); Liked Songs is not in it
+ (void)library:(NSString *)filter offset:(NSInteger)offset limit:(NSInteger)limit
     completion:(void (^)(NSArray *items, NSInteger total, NSError *error))completion;
+ (void)editablePlaylistsFor:(NSString *)trackURI completion:(void (^)(NSArray *playlists, NSError *error))completion;
+ (void)profile:(void (^)(NSString *name, NSString *imageURL))completion;

// Saving (Liked Songs, albums, followed artists, playlists and podcasts) and playlist edits. A change posts
// S6LibraryDidChangeNotification.
+ (void)areSaved:(NSArray *)uris completion:(void (^)(NSArray *saved, NSError *error))completion;   // NSNumber (BOOL) per uri
+ (void)setSaved:(BOOL)saved uris:(NSArray *)uris completion:(void (^)(NSError *error))completion;
+ (void)addTracks:(NSArray *)uris toPlaylist:(NSString *)playlistURI completion:(void (^)(NSError *error))completion;
+ (void)createPlaylistNamed:(NSString *)name completion:(void (^)(S6Playlist *playlist, NSError *error))completion;
+ (void)removeTrackUIDs:(NSArray *)uids fromPlaylist:(NSString *)playlistURI completion:(void (^)(NSError *error))completion;

@end
