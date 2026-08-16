#import "LTTabBarController.h"
#import "LTMiniPlayerView.h"
#import "LTPlayerViewController.h"

static const CGFloat LTMiniPlayerHeight = 48.0f;

@interface LTTabBarController () <UITabBarControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong, readwrite) LTMiniPlayerView *miniPlayerView;
@end

@implementation LTTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.miniPlayerView = [[LTMiniPlayerView alloc] initWithFrame:CGRectZero];
    self.miniPlayerView.hidden = YES;
    __weak LTTabBarController *weakSelf = self;
    self.miniPlayerView.onOpenPlayer = ^{
        [weakSelf openPlayer];
    };
    [self.view addSubview:self.miniPlayerView];

    self.delegate = self;
    for (UIViewController *vc in self.viewControllers) {
        if ([vc isKindOfClass:[UINavigationController class]]) {
            ((UINavigationController *)vc).delegate = self;
        }
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(miniPlayerVisibilityChanged:)
                                                 name:LTMiniPlayerVisibilityDidChangeNotification
                                               object:self.miniPlayerView];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat tabTop = self.tabBar.frame.origin.y;
    self.miniPlayerView.frame = CGRectMake(0.0f, tabTop - LTMiniPlayerHeight, width, LTMiniPlayerHeight);
    [self.miniPlayerView refresh];
    [self applyMiniPlayerInset];
}

- (void)miniPlayerVisibilityChanged:(NSNotification *)notification {
    [self applyMiniPlayerInset];
}

- (void)applyMiniPlayerInset {
    CGFloat inset = self.miniPlayerView.hidden ? 0.0f : LTMiniPlayerHeight;
    UIScrollView *scrollView = [self visibleScrollView];
    if (!scrollView) return;
    if (scrollView.contentInset.bottom != inset) {
        scrollView.contentInset = UIEdgeInsetsMake(scrollView.contentInset.top,
                                                   scrollView.contentInset.left,
                                                   inset,
                                                   scrollView.contentInset.right);
    }
    scrollView.scrollIndicatorInsets = UIEdgeInsetsMake(scrollView.scrollIndicatorInsets.top,
                                                        scrollView.scrollIndicatorInsets.left,
                                                        inset,
                                                        scrollView.scrollIndicatorInsets.right);
}

- (UIScrollView *)visibleScrollView {
    UIViewController *top = self.selectedViewController;
    if ([top isKindOfClass:[UINavigationController class]]) {
        top = [(UINavigationController *)top topViewController];
    }
    if (![top isViewLoaded]) return nil;
    return [self scrollViewInView:top.view];
}

- (UIScrollView *)scrollViewInView:(UIView *)view {
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    if ([view isKindOfClass:[UISearchBar class]]) return nil;
    if ([view isKindOfClass:[UIScrollView class]]) return (UIScrollView *)view;
    for (UIView *sub in view.subviews) {
        UIScrollView *found = [self scrollViewInView:sub];
        if (found) return found;
    }
    return nil;
}

#pragma mark - UITabBarControllerDelegate

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    [self applyMiniPlayerInset];
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    [self applyMiniPlayerInset];
}

- (void)openPlayer {
    UINavigationController *nav = (UINavigationController *)self.selectedViewController;
    if (![nav isKindOfClass:[UINavigationController class]]) return;
    LTPlayerViewController *player = [[LTPlayerViewController alloc] init];
    [nav pushViewController:player animated:YES];
}

@end
