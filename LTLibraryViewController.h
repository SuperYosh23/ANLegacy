#import <UIKit/UIKit.h>
#import "LTSeedSearchViewController.h"

@interface LTLibraryViewController : UIViewController <UIActionSheetDelegate, LTSeedSearchViewControllerDelegate>

- (void)showPlaylistsSegment;   // used by the home screen quick action
- (void)showSongsSegment;

@end