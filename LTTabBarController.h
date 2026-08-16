#import <UIKit/UIKit.h>

@class LTMiniPlayerView;

@interface LTTabBarController : UITabBarController

@property (nonatomic, strong, readonly) LTMiniPlayerView *miniPlayerView;

- (void)openPlayer;

@end
