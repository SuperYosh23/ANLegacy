#import "LTTabBarController.h"
#import "LTTransitionSettings.h"
#import "LTLog.h"
#import <QuartzCore/QuartzCore.h>

@interface LTTabBarController () <UITabBarControllerDelegate>
@property (nonatomic, strong) UIImageView *contentSnapshot;
@property (nonatomic, assign) NSInteger slideFromIndex;
@property (nonatomic, assign) NSInteger slideToIndex;
@property (nonatomic, assign) BOOL fading;
@property (nonatomic, assign) CGRect slideContentRect;
@end

@implementation LTTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;
}

+ (UIImage *)snapshotContentOfView:(UIView *)view inRect:(CGRect)rect scale:(CGFloat)scale {
    if (rect.size.width < 1.0f || rect.size.height < 1.0f) return nil;
    CGSize px = CGSizeMake(ceilf(rect.size.width * scale), ceilf(rect.size.height * scale));
    if (px.width < 1.0f || px.height < 1.0f) return nil;
    UIGraphicsBeginImageContext(px);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(ctx, scale, scale);
    if (rect.origin.x != 0.0f || rect.origin.y != 0.0f) {
        CGContextTranslateCTM(ctx, -rect.origin.x, -rect.origin.y);
    }
    [view.layer renderInContext:ctx];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (CGRect)contentRectForTabBarController:(UITabBarController *)tabBarController {
    UIView *rootView = tabBarController.view;
    UINavigationController *nav = [tabBarController.selectedViewController isKindOfClass:[UINavigationController class]]
        ? (UINavigationController *)tabBarController.selectedViewController
        : nil;
    CGFloat width = rootView.bounds.size.width;
    CGFloat height = rootView.bounds.size.height;
    CGFloat contentTop = nav ? CGRectGetMaxY(nav.navigationBar.frame) : 0.0f;
    CGFloat tabHeight = tabBarController.tabBar.frame.size.height;
    return CGRectMake(0.0f, contentTop, width, height - contentTop - tabHeight);
}

#pragma mark - UITabBarControllerDelegate

// Capture the outgoing CONTENT area only (bars are left alone). Snapshot is
// taken fresh at tap time so it's never outdated.
- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController {
    if (viewController == tabBarController.selectedViewController || self.fading) return NO;
    UIView *fromView = tabBarController.selectedViewController.view;
    if (!fromView || !fromView.window) return YES;

    self.slideFromIndex = (NSInteger)tabBarController.selectedIndex;
    self.slideToIndex = (NSInteger)[tabBarController.viewControllers indexOfObject:viewController];
    self.slideContentRect = [self contentRectForTabBarController:tabBarController];
    return YES;
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    NSInteger fromIndex = self.slideFromIndex;
    NSInteger toIndex = (NSInteger)[tabBarController.viewControllers indexOfObject:viewController];
    if (fromIndex == toIndex) return;

    // Animations disabled → instant switch.
    if (![LTTransitionSettings animationsEnabled]) return;

    CGRect rect = self.slideContentRect;
    if (rect.size.width < 1.0f) return;

    // Render the outgoing content now (the incoming real view is already drawn
    // underneath and stays fully sharp — we only fade the old content over it).
    CGFloat scale = (NSInteger)[UIDevice currentDevice].systemVersion.intValue >= 7 ? 1.0f : 0.75f;
    UINavigationController *fromNav = [self.viewControllers objectAtIndex:(NSUInteger)fromIndex];
    UIView *fromView = [fromNav isKindOfClass:[UINavigationController class]] ? fromNav.view : tabBarController.view;
    UIImage *image = [LTTabBarController snapshotContentOfView:fromView inRect:rect scale:scale];
    if (!image) return;

    UIImageView *snapshot = [[UIImageView alloc] initWithImage:image];
    snapshot.frame = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);

    // Ensure the incoming view is in place (its bars stay; only content fades).
    viewController.view.frame =
        CGRectMake(0.0f, 0.0f, tabBarController.view.bounds.size.width,
                   tabBarController.view.bounds.size.height - tabBarController.tabBar.frame.size.height);
    [tabBarController.view bringSubviewToFront:viewController.view];
    [tabBarController.view addSubview:snapshot];

    self.fading = YES;
    [UIView animateWithDuration:[LTTransitionSettings durationFor:0.14f]
        delay:0.0f
        options:UIViewAnimationOptionCurveEaseInOut
        animations:^{
            snapshot.alpha = 0.0f;
        }
        completion:^(BOOL finished) {
            [snapshot removeFromSuperview];
            self.fading = NO;
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
