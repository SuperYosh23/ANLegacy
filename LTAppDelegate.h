#import <UIKit/UIKit.h>

@interface LTAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;

+ (UITabBarController *)makeTabBarController;
+ (void)applyDisplayModeAnimated:(BOOL)animated;

@end
