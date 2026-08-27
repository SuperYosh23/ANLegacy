#import "LTTabBarController.h"
#import "LTTransitionSettings.h"
#import <QuartzCore/QuartzCore.h>

@interface LTTabBarController () <UITabBarControllerDelegate>
@property (nonatomic, strong) UIImageView *transitionSnapshot;
@end

@implementation LTTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;
}

#pragma mark - UITabBarControllerDelegate

// Snapshot the outgoing page so didSelect can cross-fade it away.
- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController {
    if (viewController == tabBarController.selectedViewController || self.transitionSnapshot) return NO;
    UIView *fromView = tabBarController.selectedViewController.view;
    if (!fromView || !fromView.window) return YES;

    UIGraphicsBeginImageContextWithOptions(fromView.bounds.size, YES, 0.0f);
    [fromView.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    self.transitionSnapshot = [[UIImageView alloc] initWithImage:image];
    self.transitionSnapshot.frame = fromView.frame;
    return YES;
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    UIImageView *snapshot = self.transitionSnapshot;
    self.transitionSnapshot = nil;
    if (!snapshot) return;

    [tabBarController.view addSubview:snapshot];
    viewController.view.alpha = 0.0f;
    [UIView animateWithDuration:[LTTransitionSettings durationFor:0.15f]
        delay:0.0f
        options:UIViewAnimationOptionCurveEaseOut
        animations:^{
            viewController.view.alpha = 1.0f;
            snapshot.alpha = 0.0f;
        }
        completion:^(BOOL finished) {
            [snapshot removeFromSuperview];
        }];
}

#pragma mark - Navigation

- (void)showNowPlaying {
    NSInteger index = (NSInteger)self.viewControllers.count - 1;
    if (self.selectedIndex != index) {
        self.selectedIndex = index;
    }
}

@end
