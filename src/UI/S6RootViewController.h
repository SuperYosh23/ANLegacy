#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, S6Section) {
    S6SectionHome = 0,
    S6SectionSearch,
    S6SectionLikedSongs,
    S6SectionPlaylists,
    S6SectionAlbums,
    S6SectionArtists,
    S6SectionPodcasts,
    S6SectionSettings,
    S6SectionLibrary,       // the iPhone's library tab (playlists, albums, artists, podcasts behind one switch)
};

// The frame of the app. iPad: the sidebar on the left, the content on the right, the player bar along the bottom.
// iPhone: the content, the compact player bar and the tab bar. The login screen covers everything while no account
// is logged in.
@interface S6RootViewController : UIViewController

+ (instancetype)shared;

- (void)showSection:(S6Section)section;
@property (nonatomic, readonly) S6Section section;
- (UINavigationController *)contentNavigationController;   // the one on screen

- (void)pushViewController:(UIViewController *)controller;  // onto the content on screen (closing what covers it)
- (void)presentNowPlaying;
- (void)presentNowPlayingPanel:(NSInteger)panel;            // S6NowPlayingPanel
- (void)presentSheet:(UIViewController *)controller;        // in its own navigation bar; a form sheet on the iPad
- (void)showToast:(NSString *)text;

- (UIViewController *)topController;                        // for the debug commands
- (void)goBack;

@end
