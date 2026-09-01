#import <UIKit/UIKit.h>

@class LTTrack;

// Shared "Add to Queue / Add to Playlist / Download" context menu for a song.
// Presents a UIActionSheet (or playlist picker / download flow) from any screen.
@interface LTSongMenu : NSObject <UIActionSheetDelegate, UIAlertViewDelegate>

- (void)presentForTrack:(LTTrack *)track fromViewController:(UIViewController *)viewController;

@end
