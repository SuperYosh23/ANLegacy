@import UIKit;

@interface LTTabBarController : UITabBarController

// Called whenever the selected tab changes (taps, programmatic selection, or
// the iPad sidebar). Used to keep external chrome like the sidebar in sync.
@property (nonatomic, copy) void (^selectionDidChange)(NSInteger index);

// Set by the iPad split container while the tab bar is parked away in
// landscape; the controller then re-asserts a bar-less, full-height layout on
// every layout pass so no dead strip is left beneath the selected controller.
@property (nonatomic, assign) BOOL tabBarForcedHidden;

- (void)showNowPlaying;

@end
