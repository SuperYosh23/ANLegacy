#import <UIKit/UIKit.h>
#import "S6RootViewController.h"

@class S6Playlist;

// The iPad's left column, as in Spotify's iPad app of 2012: Home and Search, your library, your playlists, and the
// account with Settings at the bottom
@interface S6SidebarViewController : UIViewController
@property (nonatomic, copy) void (^onSection)(S6Section section);
@property (nonatomic, copy) void (^onPlaylist)(S6Playlist *playlist);
- (void)selectSection:(S6Section)section;
- (void)selectPlaylist:(NSString *)playlistId;
@end
