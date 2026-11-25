#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// What Spotify describes, in the shapes the screens use: from the GraphQL API the desktop and web clients browse with
// (…FromGraphQL), and the older Web API JSON (…FromJSON, also the saved queue)

@interface S6Image : NSObject
+ (NSString *)urlIn:(id)images forSize:(CGFloat)pixels;   // the smallest image at least this big (else the biggest)
@end

@interface S6Artist : NSObject
@property (nonatomic, copy) NSString *artistId;
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray *images;           // JSON image objects
@property (nonatomic) NSInteger followers;
@property (nonatomic) NSInteger monthlyListeners;
@property (nonatomic, copy) NSArray *genres;
@property (nonatomic) BOOL saved;                      // followed by the user
+ (instancetype)artistFromJSON:(NSDictionary *)json;
+ (instancetype)artistFromGraphQL:(NSDictionary *)data;
- (NSString *)imageURLForSize:(CGFloat)pixels;
@end

@interface S6Album : NSObject
@property (nonatomic, copy) NSString *albumId;
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray *artists;          // S6Artist
@property (nonatomic, copy) NSArray *images;
@property (nonatomic, copy) NSString *albumType;       // album, single, compilation
@property (nonatomic, copy) NSString *releaseDate;
@property (nonatomic) NSInteger totalTracks;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSArray *tracks;           // S6Track, when the album was fetched whole
@property (nonatomic) BOOL saved;
+ (instancetype)albumFromJSON:(NSDictionary *)json;
+ (instancetype)albumFromGraphQL:(NSDictionary *)data;
- (NSString *)imageURLForSize:(CGFloat)pixels;
- (NSString *)artistNames;
- (NSString *)year;
@end

@interface S6Track : NSObject
@property (nonatomic, copy) NSString *trackId;         // base62; nil for local files
@property (nonatomic, copy) NSString *uri;             // spotify:track:... or spotify:episode:...
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray *artists;          // S6Artist
@property (nonatomic, strong) S6Album *album;
@property (nonatomic) NSInteger durationMs;
@property (nonatomic) BOOL explicitContent;
@property (nonatomic) BOOL playable;
@property (nonatomic) BOOL isEpisode;
@property (nonatomic) NSInteger trackNumber;
@property (nonatomic) NSInteger discNumber;
@property (nonatomic, copy) NSString *addedAt;         // in a playlist or the library
@property (nonatomic, copy) NSString *uid;             // its place in a playlist (removing it needs this)
@property (nonatomic) long long playcount;
@property (nonatomic, copy) NSString *releaseDate;     // episodes: "2026-06-03"
+ (instancetype)trackFromJSON:(NSDictionary *)json;    // a track or an episode object
+ (instancetype)trackFromJSON:(NSDictionary *)json album:(S6Album *)album;   // album tracks come without their album
+ (instancetype)trackFromGraphQL:(NSDictionary *)data album:(S6Album *)album; // a Track or an Episode
- (NSString *)artistNames;
- (NSString *)imageURLForSize:(CGFloat)pixels;
- (NSDictionary *)toJSON;                              // for the saved queue
@end

@interface S6Playlist : NSObject
@property (nonatomic, copy) NSString *playlistId;
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *descriptionText;
@property (nonatomic, copy) NSString *ownerName;
@property (nonatomic, copy) NSString *ownerId;
@property (nonatomic, copy) NSArray *images;
@property (nonatomic) NSInteger totalTracks;
@property (nonatomic) NSInteger followers;
@property (nonatomic) BOOL collaborative;
@property (nonatomic, copy) NSString *snapshotId;
@property (nonatomic) BOOL editable;                   // the user may add and remove songs
@property (nonatomic) BOOL saved;                      // in the user's library (followed)
+ (instancetype)playlistFromJSON:(NSDictionary *)json;
+ (instancetype)playlistFromGraphQL:(NSDictionary *)data;
- (NSString *)imageURLForSize:(CGFloat)pixels;
@end

@interface S6Show : NSObject
@property (nonatomic, copy) NSString *showId;
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *publisher;
@property (nonatomic, copy) NSString *descriptionText;
@property (nonatomic, copy) NSArray *images;
@property (nonatomic) BOOL saved;
+ (instancetype)showFromJSON:(NSDictionary *)json;
+ (instancetype)showFromGraphQL:(NSDictionary *)data;
- (NSString *)imageURLForSize:(CGFloat)pixels;
@end

// Any entity of the GraphQL API as its model (S6Track for tracks and episodes, S6Album, S6Artist, S6Playlist, S6Show),
// its wrappers ({data: ...}, {item: ...}, {content: ...}) unwrapped; nil for anything else (Liked Songs, users, errors)
id S6EntityFromGraphQL(NSDictionary *node);

// Text from Spotify's HTML descriptions: tags out, entities decoded
NSString *S6PlainText(NSString *html);

// "spotify:track:abc" -> "track", "abc"
NSString *S6URIType(NSString *uri);
NSString *S6URIId(NSString *uri);
NSString *S6FormatDurationMs(NSInteger ms);   // 3:05, 1:02:03
