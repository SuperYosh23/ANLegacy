#import "S6ListViewController.h"

typedef NS_ENUM(NSInteger, S6LibraryMode) {
    S6LibraryPlaylists = 0,
    S6LibraryAlbums,
    S6LibraryArtists,
    S6LibraryPodcasts,
};

// Your library: playlists (Liked Songs first, a new one from the + button), saved albums, followed artists, podcasts.
// With the switcher (iPhone) a segmented control changes between them; on the iPad the sidebar does.
@interface S6LibraryViewController : S6ListViewController
- (instancetype)initWithMode:(S6LibraryMode)mode switcher:(BOOL)switcher;
@property (nonatomic) S6LibraryMode mode;
@end

// Picks one of your playlists (for "Add to playlist"); nil when cancelled
@interface S6PlaylistPickerViewController : S6ListViewController
- (instancetype)initWithCompletion:(void (^)(id playlist))completion;
@property (nonatomic, copy) NSString *trackURI;     // the song to add (Spotify marks the playlists it is already in)
@end
