#import <UIKit/UIKit.h>

@interface LTAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;

+ (void)applyDisplayModeAnimated:(BOOL)animated;

@end
