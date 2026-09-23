#import "LTTabBarController.h"
#import "LTAppTabBar.h"
#import "LTTransitionSettings.h"
#import "LTLog.h"
#import <QuartzCore/QuartzCore.h>

@interface LTTabBarController () <UITabBarControllerDelegate>
@property (nonatomic, strong) UIImageView *contentSnapshot;
@property (nonatomic, assign) NSInteger slideFromIndex;
@property (nonatomic, assign) NSInteger slideToIndex;
@property (nonatomic, assign) BOOL fading;
@property (nonatomic, assign) CGRect slideContentRect;
@property (nonatomic, assign) NSInteger lastAnnouncedIndex;
@end

@implementation LTTabBarController

- (instancetype)init {
    self = [super init];
    if (self) {
        // Swap in LTAppTabBar (compact trait in one-handed mode) before the
        // controller builds its default bar.
        [self setValue:[[LTAppTabBar alloc] init] forKey:@"tabBar"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;
    self.lastAnnouncedIndex = NSNotFound;
}

// On the iPad the split container parks the tab bar away in landscape. Even so,
// UITabBarController keeps reserving the bar's ~49pt and lays the child short,
// leaving a dead black strip beneath the player. This re-asserts the intended
// layout on EVERY pass — collapsing the bar to zero height and pushing the
// selected child (and any navigation content inside it) to full bounds — so
// whatever pass UIKit runs first, ours is the final word.
- (void)assertForcedHiddenTabBarLayout {
    CGRect b = self.view.bounds;
    if (b.size.width < 1.0f || b.size.height < 1.0f) return;

    BOOL barDocked = (!self.tabBar.hidden &&
                      CGRectGetHeight(self.tabBar.frame) > 0.5f &&
                      CGRectGetMaxY(self.tabBar.frame) <= b.size.height + 0.5f &&
                      CGRectGetMaxY(self.tabBar.frame) >= b.size.height - 0.5f);

    if (self.tabBarForcedHidden || !barDocked) {
        self.tabBar.hidden = YES;
        self.tabBar.frame = CGRectMake(0.0f, b.size.height, b.size.width, 0.0f);
        UIViewController *sel = self.selectedViewController;
        if (sel) {
            sel.view.frame = b;
            if ([sel isKindOfClass:[UINavigationController class]]) {
                UIViewController *top = ((UINavigationController *)sel).topViewController;
                if (top && top.view.superview) top.view.frame = b;
            }
        }
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self assertForcedHiddenTabBarLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self assertForcedHiddenTabBarLayout];
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
    CGFloat tabHeight = [self effectiveTabBarHeightForBounds:rootView.bounds];
    return CGRectMake(0.0f, contentTop, width, height - contentTop - tabHeight);
}

// Height the tab bar actually occupies in the given bounds. Uses the frame
// position, not the `hidden` flag: on the iPad the split container docks the
// bar offscreen in landscape, and UITabBarController keeps even a hidden bar's
// frame in place, which would otherwise leave a dead strip under the player.
- (CGFloat)effectiveTabBarHeightForBounds:(CGRect)bounds {
    if (self.tabBar.hidden) return 0.0f;
    CGRect barFrame = self.tabBar.frame;
    if (barFrame.size.height < 1.0f) return 0.0f;
    if (CGRectGetMaxY(barFrame) > bounds.size.height + 0.5f) return 0.0f;
    if (CGRectGetMaxY(barFrame) < 0.5f) return 0.0f;
    return CGRectGetHeight(barFrame);
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
    [self announceSelectionTo:toIndex];

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
    CGRect tabBounds = tabBarController.view.bounds;
    viewController.view.frame =
        CGRectMake(0.0f, 0.0f, tabBounds.size.width,
                   tabBounds.size.height - [self effectiveTabBarHeightForBounds:tabBounds]);
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

// Announce the new selection exactly once no matter how it changed. Programmatic
// selection (sidebar taps, showNowPlaying) does not reliably reach the tab-bar
// delegate, so the setter announces too, and the last-seen index dedupes it
// against the delegate path to avoid double-firing.
- (void)announceSelectionTo:(NSInteger)index {
    if (index == self.lastAnnouncedIndex) return;
    self.lastAnnouncedIndex = index;
    if (self.selectionDidChange) self.selectionDidChange(index);
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];
    [self announceSelectionTo:(NSInteger)selectedIndex];
}

@end
