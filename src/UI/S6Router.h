#import <UIKit/UIKit.h>

@class S6Album, S6Artist, S6Playlist, S6Show, S6Track;

// A UIActionSheet with a block per button (the delegate keeps itself alive while the sheet is up)
@interface S6ActionSheet : NSObject
- (instancetype)initWithTitle:(NSString *)title;
- (void)addButton:(NSString *)title action:(dispatch_block_t)action;
- (void)addDestructiveButton:(NSString *)title action:(dispatch_block_t)action;
- (void)showFromView:(UIView *)view inController:(UIViewController *)controller;
+ (BOOL)pressButtonTitled:(NSString *)title;      // the sheet on screen (debug commands)
@end

// Going places: album, artist, playlist and show pages, Spotify links, the actions of a song, now playing
@interface S6Router : NSObject

+ (void)openAlbum:(S6Album *)album;
+ (void)openArtist:(S6Artist *)artist;
+ (void)openPlaylist:(S6Playlist *)playlist;
+ (void)openShow:(S6Show *)show;
+ (void)openURI:(NSString *)uri;                   // spotify:album:..., spotify:artist:..., spotify:playlist:..., open.spotify.com links
+ (void)playHandoff:(NSDictionary *)metadata;
+ (void)cancelHandoff;
+ (void)openLikedSongs;
+ (void)openItem:(id)item;                         // any shelf item: album, playlist, artist, show, a song or episode (plays), a category
+ (void)push:(UIViewController *)controller;       // onto the content that is on screen (closing what covers it)
+ (void)playRadioFor:(S6Track *)track;             // the song and similar ones after it

+ (void)showActionsForTrack:(S6Track *)track fromView:(UIView *)view inController:(UIViewController *)controller
                   playlist:(S6Playlist *)playlist;          // `playlist`: it is in this playlist (removing becomes possible)
+ (void)addTrackToPlaylist:(S6Track *)track;
+ (void)showNowPlaying;
+ (void)showSleepTimerFromView:(UIView *)view inController:(UIViewController *)controller;
+ (void)toast:(NSString *)text;                    // a short note in the middle of the screen

@end
