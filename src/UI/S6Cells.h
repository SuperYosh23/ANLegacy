#import <UIKit/UIKit.h>

@class S6Track, S6ImageView;

// A song in a list: artwork or its number, the title (green while it plays), artists, length, the "E" badge, "…"
@interface S6TrackCell : UITableViewCell
@property (nonatomic, strong, readonly) S6ImageView *art;
@property (nonatomic, strong, readonly) UIButton *moreButton;
@property (nonatomic) BOOL showsArt;              // NO: the track number stands there (albums)
- (void)showTrack:(S6Track *)track number:(NSInteger)number;
@end

// An album, playlist, artist or show in a list: artwork (round for artists), two lines of text
@interface S6MediaCell : UITableViewCell
@property (nonatomic, strong, readonly) S6ImageView *art;
@property (nonatomic) BOOL round;
- (void)showTitle:(NSString *)title subtitle:(NSString *)subtitle imageURL:(NSString *)url;
@end

// One card of a shelf: square artwork with a title and a subtitle under it
@interface S6CardView : UIControl
@property (nonatomic, strong, readonly) S6ImageView *art;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;
@property (nonatomic) BOOL round;
@property (nonatomic, strong) id item;            // what the card stands for
@end

// A row with a sideways-scrolling shelf of cards ("Recently played", "Your top artists"...)
@interface S6ShelfCell : UITableViewCell
@property (nonatomic, copy) void (^onSelect)(id item);
+ (CGFloat)heightForCardWidth:(CGFloat)width;
- (void)showItems:(NSArray *)items cardWidth:(CGFloat)width;   // items: NSDictionary {title, subtitle, image, round, item}
@end

// A row of coloured tiles (the browse categories): items NSDictionary {title, image, color, uri}
@interface S6TileRowCell : UITableViewCell
@property (nonatomic, copy) void (^onSelect)(id item);
+ (CGFloat)heightForWidth:(CGFloat)width columns:(NSInteger)columns;
- (void)showTiles:(NSArray *)tiles columns:(NSInteger)columns;
@end

// The title of a section in the style of the time: small capitals on a dark bar
UIView *S6SectionHeader(NSString *title, CGFloat width);

// A shelf card for anything that can stand on a shelf: an album, playlist, artist, show, episode or song, or a browse
// category (NSDictionary {title, uri, image})
NSDictionary *S6CardFor(id item);
