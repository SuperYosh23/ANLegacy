#import <UIKit/UIKit.h>

extern NSString *const LTMiniPlayerVisibilityDidChangeNotification;
extern NSString *const LTNowPlayingDidAppearNotification;
extern NSString *const LTNowPlayingDidDisappearNotification;

@interface LTMiniPlayerView : UIView

@property (nonatomic, copy) void (^onOpenPlayer)(void);

- (void)refresh;

@end
