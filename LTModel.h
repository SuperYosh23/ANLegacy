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
@property (nonatomic, strong) NSMutableArray *tracks;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)playlistWithDictionary:(NSDictionary *)dict;
@end
