#import "S6ListViewController.h"

@class S6Album, S6Playlist, S6Show;

// A list of songs with a header: an album, a playlist, the liked songs, a podcast's episodes, or any list given
@interface S6TrackListViewController : S6ListViewController

- (instancetype)initWithAlbum:(S6Album *)album;
- (instancetype)initWithPlaylist:(S6Playlist *)playlist;
- (instancetype)initWithShow:(S6Show *)show;
- (instancetype)initLikedSongs;
- (instancetype)initWithTracks:(NSArray *)tracks title:(NSString *)title contextURI:(NSString *)uri;

@end
