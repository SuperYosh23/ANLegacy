#import "LTTabBarController.h"
#import "LTPlayerController.h"
#import <QuartzCore/QuartzCore.h>

@interface LTTabBarController () <UITabBarControllerDelegate>
@property (nonatomic, strong) UIImageView *transitionSnapshot;
@end

@implementation LTTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerStateChanged:)
                                                 name:LTPlayerTrackDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerStateChanged:)
                                                 name:LTPlayerStateDidChangeNotification
                                               object:nil];
    [self refreshNowPlayingIcon];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Now Playing indicator

- (UITabBarItem *)nowPlayingItem {
    UINavigationController *nav = [self.viewControllers lastObject];
    if (![nav isKindOfClass:[UINavigationController class]]) return nil;
    return [nav.viewControllers firstObject].tabBarItem;
}

- (void)refreshNowPlayingIcon {
    UITabBarItem *item = [self nowPlayingItem];
    if (!item) return;
    BOOL playing = [[LTPlayerController sharedController] isPlaying];
    // Plain .image is stencil-rendered gray by iOS 6 unless the tab is
    // selected, so supply finished images that render verbatim instead.
    UIImage *blue = [UIImage imageNamed:@"IcoPlayBlue"];
    UIImage *gray = [UIImage imageNamed:@"IcoPlay"];
    [item setFinishedSelectedImage:blue withFinishedUnselectedImage:(playing ? blue : gray)];
}

- (void)playerStateChanged:(NSNotification *)notification {
    [self refreshNowPlayingIcon];
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
    [UIView animateWithDuration:0.15f
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
