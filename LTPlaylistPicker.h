#import <UIKit/UIKit.h>
#import "LTPlaylistStore.h"

@interface LTPlaylistPicker : UIViewController <UIAlertViewDelegate>
// Custom bottom-panel replacement for UIActionSheet-based playlist picking.
// Lists playlists by object reference (immune to duplicate names), offers
// inline "New Playlist..." creation, and dismisses on outside tap.
+ (void)presentFromViewController:(UIViewController *)viewController
                       panelTitle:(NSString *)panelTitle
                        onPicked:(void (^)(LTLocalPlaylist *playlist))picked
                     onCreateNew:(void (^)(NSString *name))createNew;

@end
