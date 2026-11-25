#import <UIKit/UIKit.h>

@class LTLocalPlaylist;

// The card iOS shows when a playlist row is pressed in but not fully committed.
//
// Presented by UIKit into its own peek container, so it must not assume a
// navigation bar, a tab bar, or that it owns the window. Fully pressing in hands
// off to the real LTLocalPlaylistDetailViewController instead, which is why this
// is read-only by design.
@interface LTPlaylistPeekViewController : UIViewController

- (instancetype)initWithPlaylist:(LTLocalPlaylist *)playlist;

// Read back by the coordinator when a peek is committed.
@property (nonatomic, strong, readonly) LTLocalPlaylist *playlist;

@end