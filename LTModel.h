#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, LTBrowseKind) {
    LTBrowseKindAlbum = 0,
    LTBrowseKindArtist,
    LTBrowseKindPlaylist,
};

@interface LTTrack : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *thumbnailURL;
@property (nonatomic, assign) NSTimeInterval duration;

// Play count for a track, when the page it came from supplied one (-1 for
// unknown). Display only: deliberately not part of -dictionaryRepresentation,
// so it is never written to disk or sent in a sync payload. A count is a
// property of a listing at a moment in time, not of the song.
@property (nonatomic, assign) long long playCount;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)trackWithDictionary:(NSDictionary *)dict;
@end

@interface LTBrowseItem : NSObject
@property (nonatomic, assign) LTBrowseKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *browseId;
@property (nonatomic, copy) NSString *thumbnailURL;
@end

@interface LTLocalPlaylist : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *coverPath;
@property (nonatomic, strong) NSMutableArray *tracks;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)playlistWithDictionary:(NSDictionary *)dict;
@end

@interface LTStationSeed : NSObject
@property (nonatomic, copy) NSString *type; // track|artist|album
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *thumbnailURL;
@property (nonatomic, copy) NSString *browseId; // YouTube browse ID for artist/album
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)seedWithDictionary:(NSDictionary *)dict;
@end

@interface LTStation : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray *seeds;
@property (nonatomic, copy) NSString *coverPath;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)stationWithDictionary:(NSDictionary *)dict;
@end
