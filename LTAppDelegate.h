#import <UIKit/UIKit.h>

@class LTTabBarController;

@interface LTAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;

+ (LTTabBarController *)makeTabBarController;
+ (UIViewController *)standardRootViewController;
+ (void)applyDisplayModeAnimated:(BOOL)animated;

@end
