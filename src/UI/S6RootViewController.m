#import "S6RootViewController.h"
#import "S6SidebarViewController.h"
#import "S6LoginViewController.h"
#import "S6SettingsViewController.h"
#import "S6HomeViewController.h"
#import "S6SearchViewController.h"
#import "S6LibraryViewController.h"
#import "S6TrackListViewController.h"
#import "S6NowPlayingViewController.h"
#import "S6PlayerBar.h"
#import "S6Player.h"
#import "S6Session.h"
#import "S6Settings.h"
#import "S6Models.h"
#import "S6Theme.h"
#import "S6Modern.h"
#import "S6Common.h"
#import "LTTransitionSettings.h"

static __unsafe_unretained S6RootViewController *S6RootShared;

@interface S6RootViewController () <UITabBarDelegate>
@property (nonatomic, strong) NSMutableDictionary *navs;            // @(S6Section) -> UINavigationController
@property (nonatomic, strong) UINavigationController *current;
@property (nonatomic, readwrite) S6Section section;
@property (nonatomic, strong) S6SidebarViewController *sidebar;     // iPad
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) UITabBar *tabBar;                     // iPhone
@property (nonatomic, strong) NSArray *tabSections;
@property (nonatomic, strong) S6PlayerBar *playerBar;
@property (nonatomic, strong) S6LoginViewController *login;
@property (nonatomic, strong) UILabel *toast;
@property (nonatomic) NSUInteger toastGeneration;
@end

@implementation S6RootViewController

+ (instancetype)shared { return S6RootShared; }

- (instancetype)init
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        S6RootShared = self;
        _navs = [NSMutableDictionary dictionary];
        _section = (S6Section)-1;
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)viewDidLoad
{
    [super viewDidLoad];
    S6Theme *theme = [S6Theme shared];
    self.view.backgroundColor = [theme plainBackgroundColor];
    BOOL pad = S6IsPad();
    if (pad) {
        self.sidebar = [[S6SidebarViewController alloc] init];
        __unsafe_unretained S6RootViewController *weakSelf = self;
        self.sidebar.onSection = ^(S6Section section) { [weakSelf showSection:section]; };
        self.sidebar.onPlaylist = ^(S6Playlist *playlist) { [weakSelf showSidebarPlaylist:playlist]; };
        [self addChildViewController:self.sidebar];
        [self.view addSubview:self.sidebar.view];
        [self.sidebar didMoveToParentViewController:self];
        self.divider = [[UIView alloc] initWithFrame:CGRectZero];
        self.divider.backgroundColor = [UIColor colorWithWhite:0 alpha:0.9];
        [self.view addSubview:self.divider];
    } else {
        self.tabSections = @[ @(S6SectionHome), @(S6SectionSearch), @(S6SectionLibrary), @(S6SectionSettings) ];
        NSArray *titles = @[ L(@"Home"), L(@"Search"), L(@"Your Library"), L(@"Settings") ];
        NSArray *icons = @[ @(S6IconHome), @(S6IconSearch), @(S6IconLibrary), @(S6IconSettings) ];
        NSMutableArray *items = [NSMutableArray array];
        for (NSUInteger i = 0; i < titles.count; i++) {
            UITabBarItem *item = [[UITabBarItem alloc] initWithTitle:titles[i] image:[theme icon:(S6Icon)[icons[i] integerValue] size:28] tag:(NSInteger)i];
            [items addObject:item];
        }
        self.tabBar = [[UITabBar alloc] initWithFrame:CGRectZero];
        self.tabBar.items = items;
        self.tabBar.delegate = self;
        [self.view addSubview:self.tabBar];
    }
    self.playerBar = [[S6PlayerBar alloc] initWithFrame:CGRectZero compact:!pad];
    [self.view addSubview:self.playerBar];
    [self showSection:S6SectionHome];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(sessionChanged) name:S6SessionStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(playerChanged) name:S6PlayerDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(showQueue) name:@"S6ShowQueue" object:nil];
    [nc addObserver:self selector:@selector(showLyrics) name:@"S6ShowLyrics" object:nil];
    [nc addObserver:self selector:@selector(playerFailed:) name:S6PlayerDidFailNotification object:nil];
    [self sessionChanged];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self becomeFirstResponder];   // the lock screen's and the headphones' controls
}

- (BOOL)canBecomeFirstResponder { return YES; }
- (void)remoteControlReceivedWithEvent:(UIEvent *)event { [[S6Player shared] handleRemoteEvent:event]; }

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return S6IsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)o { return S6IsPad() || o == UIInterfaceOrientationPortrait; }

#pragma mark - Layout

- (BOOL)showsPlayerBar { return S6IsPad() || [S6Player shared].currentTrack != nil; }

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGSize s = self.view.bounds.size;
    BOOL bar = [self showsPlayerBar];
    self.playerBar.hidden = !bar;
    // the home indicator of iOS 11+ (zero elsewhere): the bottom bar grows over it, its content stays above
    CGFloat home = S6SafeAreaInsets(self.view).bottom;
    if (S6IsPad()) {
        CGFloat barH = [S6PlayerBar heightCompact:NO];
        CGFloat side = s.width > s.height ? 250 : 220;
        self.sidebar.view.frame = CGRectMake(0, 0, side, s.height - barH - home);
        self.divider.frame = CGRectMake(side, 0, 1, s.height - barH - home);
        self.current.view.frame = CGRectMake(side + 1, 0, s.width - side - 1, s.height - barH - home);
        self.playerBar.frame = CGRectMake(0, s.height - barH - home, s.width, barH + home);
        self.playerBar.bottomInset = home;
    } else {
        CGFloat tabH = 49 + home, barH = bar ? [S6PlayerBar heightCompact:YES] : 0;
        self.tabBar.frame = CGRectMake(0, s.height - tabH, s.width, tabH);   // (the items sit above the indicator by themselves)
        self.playerBar.frame = CGRectMake(0, s.height - tabH - barH, s.width, [S6PlayerBar heightCompact:YES]);
        self.playerBar.bottomInset = 0;
        self.current.view.frame = CGRectMake(0, 0, s.width, s.height - tabH - barH);
    }
    self.login.view.frame = self.view.bounds;
}

#pragma mark - Sections

- (UIViewController *)rootControllerFor:(S6Section)section
{
    switch (section) {
        case S6SectionHome: return [[S6HomeViewController alloc] init];
        case S6SectionSearch: return [[S6SearchViewController alloc] init];
        case S6SectionLikedSongs: return [[S6TrackListViewController alloc] initLikedSongs];
        case S6SectionPlaylists: return [[S6LibraryViewController alloc] initWithMode:S6LibraryPlaylists switcher:NO];
        case S6SectionAlbums: return [[S6LibraryViewController alloc] initWithMode:S6LibraryAlbums switcher:NO];
        case S6SectionArtists: return [[S6LibraryViewController alloc] initWithMode:S6LibraryArtists switcher:NO];
        case S6SectionPodcasts: return [[S6LibraryViewController alloc] initWithMode:S6LibraryPodcasts switcher:NO];
        case S6SectionSettings: return [[S6SettingsViewController alloc] init];
        case S6SectionLibrary: return [[S6LibraryViewController alloc] initWithMode:S6LibraryPlaylists switcher:YES];
    }
    return nil;
}

- (UINavigationController *)navFor:(S6Section)section
{
    UINavigationController *nav = self.navs[@(section)];
    if (!nav) {
        UIViewController *root = [self rootControllerFor:section];
        if (!root) return nil;
        nav = [[UINavigationController alloc] initWithRootViewController:root];
        [[S6Theme shared] applyToNavigationBar:nav.navigationBar];
        self.navs[@(section)] = nav;
    }
    return nav;
}

- (UINavigationController *)contentNavigationController { return self.current; }

- (void)showSection:(S6Section)section
{
    UINavigationController *nav = [self navFor:section];
    if (!nav) return;
    if (nav == self.current) {
        // the section again: back to its first screen (Search: into the field)
        [nav popToRootViewControllerAnimated:YES];
        if (section == S6SectionSearch && [nav.viewControllers.firstObject isKindOfClass:[S6SearchViewController class]])
            [(S6SearchViewController *)nav.viewControllers.firstObject focusSearchField];
        return;
    }
    UINavigationController *old = self.current;
    // Containment is iOS 5+. On older systems the controllers' views still
    // work as plain subviews, so skip the calls the runtime does not provide.
    BOOL canContain = [self respondsToSelector:@selector(addChildViewController:)]
        && [UINavigationController instancesRespondToSelector:@selector(didMoveToParentViewController:)];
    if (canContain) [old willMoveToParentViewController:nil];
    [old.view removeFromSuperview];
    if (canContain) [old removeFromParentViewController];
    self.current = nav;
    self.section = section;
    if (canContain) [self addChildViewController:nav];
    [self.view insertSubview:nav.view belowSubview:self.playerBar];
    if (canContain) [nav didMoveToParentViewController:self];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self.sidebar selectSection:section];
    if (self.tabBar) {
        NSUInteger i = [self.tabSections indexOfObject:@(section)];
        if (i != NSNotFound) self.tabBar.selectedItem = self.tabBar.items[i];
    }
    if (section == S6SectionSearch && [nav.viewControllers.firstObject isKindOfClass:[S6SearchViewController class]] && nav.viewControllers.count == 1)
        [(S6SearchViewController *)nav.viewControllers.firstObject focusSearchField];
}

- (void)showSidebarPlaylist:(S6Playlist *)playlist
{
    if (!playlist.playlistId.length) return;
    [self showSection:S6SectionPlaylists];
    [self.current popToRootViewControllerAnimated:NO];
    [self.current pushViewController:[[S6TrackListViewController alloc] initWithPlaylist:playlist] animated:NO];
    [self.sidebar selectPlaylist:playlist.playlistId];
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item
{
    NSUInteger i = (NSUInteger)item.tag;
    if (i < self.tabSections.count) [self showSection:(S6Section)[self.tabSections[i] integerValue]];
}

#pragma mark - Going places

- (UIViewController *)presentedTop
{
    UIViewController *top = self;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

- (void)pushViewController:(UIViewController *)controller
{
    if (!controller) return;
    if (self.presentedViewController) {
        UINavigationController *nav = self.current;
        [self dismissViewControllerAnimated:YES completion:^{ [nav pushViewController:controller animated:YES]; }];
        return;
    }
    [self.current pushViewController:controller animated:YES];
}

- (void)presentNowPlaying { [self presentNowPlayingPanel:S6NowPlayingArt]; }

- (void)presentNowPlayingPanel:(NSInteger)panel
{
    if (![S6Player shared].currentTrack) { [self showToast:L(@"Nothing playing")]; return; }
    UIViewController *top = [self presentedTop];
    if ([top isKindOfClass:[S6NowPlayingViewController class]]) { ((S6NowPlayingViewController *)top).panel = (S6NowPlayingPanel)panel; return; }
    S6NowPlayingViewController *np = [[S6NowPlayingViewController alloc] init];
    np.panel = (S6NowPlayingPanel)panel;
    np.modalPresentationStyle = UIModalPresentationFullScreen;   // (iOS 13 and newer would present a card)
    np.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    [top presentViewController:np animated:YES completion:nil];
}

- (void)showQueue { [self presentNowPlayingPanel:S6NowPlayingQueue]; }
- (void)showLyrics { [self presentNowPlayingPanel:S6NowPlayingLyrics]; }

- (void)presentSheet:(UIViewController *)controller
{
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:controller];
    [[S6Theme shared] applyToNavigationBar:nav.navigationBar];
    if (S6IsPad()) nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [[self presentedTop] presentViewController:nav animated:YES completion:nil];
}

- (UIViewController *)topController
{
    UIViewController *top = [self presentedTop];
    if (top == self) {
        if (self.login) return self.login;
        top = self.current;
    }
    if ([top isKindOfClass:[UINavigationController class]]) top = [(UINavigationController *)top topViewController];
    return top;
}

- (void)goBack
{
    UIViewController *top = [self presentedTop];
    if (top != self) { [top.presentingViewController dismissViewControllerAnimated:YES completion:nil]; return; }
    [self.current popViewControllerAnimated:YES];
}

#pragma mark - Toast

- (void)showToast:(NSString *)text
{
    if (!text.length) return;
    UIWindow *window = self.view.window;
    if (!window) return;
    if (!self.toast) {
        self.toast = [[UILabel alloc] initWithFrame:CGRectZero];
        self.toast.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.92];
        self.toast.textColor = [UIColor whiteColor];
        self.toast.font = [[S6Theme shared] boldBodyFont];
        self.toast.textAlignment = NSTextAlignmentCenter;
        self.toast.numberOfLines = 3;
        self.toast.layer.cornerRadius = 10;
        self.toast.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        self.toast.layer.borderWidth = 1;
        self.toast.clipsToBounds = YES;
        self.toast.userInteractionEnabled = NO;
    }
    // (on the view on top, so it shows over the full player and sheets too, turned with the interface)
    UIView *host = [self presentedTop].view;
    [host addSubview:self.toast];
    self.toast.text = text;
    CGSize size = [text sizeWithFont:self.toast.font constrainedToSize:CGSizeMake(MIN(host.bounds.size.width - 60, 420), 200)];
    CGFloat w = ceilf(size.width) + 40, h = ceilf(size.height) + 24;
    CGFloat bottomBars = ([self showsPlayerBar] ? (S6IsPad() ? 72 : 54) : 0) + (self.tabBar ? 49 : 0) + S6SafeAreaInsets(self.view).bottom;
    CGFloat y = host == self.view ? host.bounds.size.height - bottomBars - h - 24 : host.bounds.size.height * 0.75 - h / 2;
    self.toast.frame = CGRectIntegral(CGRectMake((host.bounds.size.width - w) / 2, y, w, h));
    self.toast.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    self.toast.alpha = 0;
    [LTTransitionSettings animateWithDuration:0.2 animations:^{ self.toast.alpha = 1; }];
    NSUInteger generation = ++self.toastGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self.toastGeneration) return;
        [LTTransitionSettings animateWithDuration:0.3 animations:^{ self.toast.alpha = 0; } completion:^(BOOL finished) {
            if (generation == self.toastGeneration) [self.toast removeFromSuperview];
        }];
    });
}

#pragma mark - State

- (BOOL)needsLogin
{
    S6SessionState state = [S6Session shared].state;
    return ![S6Settings hasAccount] || state == S6SessionStateLoggedOut || state == S6SessionStateFailed;
}

- (void)sessionChanged
{
    BOOL needs = [self needsLogin];
    if (needs && !self.login) {
        if (self.presentedViewController) [self dismissViewControllerAnimated:NO completion:nil];
        self.login = [[S6LoginViewController alloc] init];
        BOOL canContain = [self respondsToSelector:@selector(addChildViewController:)]
            && [S6LoginViewController instancesRespondToSelector:@selector(didMoveToParentViewController:)];
        if (canContain) [self addChildViewController:self.login];
        self.login.view.frame = self.view.bounds;
        [self.view addSubview:self.login.view];
        if (canContain) [self.login didMoveToParentViewController:self];
    } else if (!needs && self.login) {
        S6LoginViewController *login = self.login;
        self.login = nil;
        BOOL canContain = [login respondsToSelector:@selector(willMoveToParentViewController:)]
            && [login respondsToSelector:@selector(removeFromParentViewController)];
        if (canContain) [login willMoveToParentViewController:nil];
        [LTTransitionSettings animateWithDuration:0.35 animations:^{ login.view.alpha = 0; } completion:^(BOOL finished) {
            [login.view removeFromSuperview];
            if (canContain) [login removeFromParentViewController];
        }];
        // a fresh start for the screens of the account
        for (UINavigationController *nav in self.navs.allValues) [nav popToRootViewControllerAnimated:NO];
        [[NSNotificationCenter defaultCenter] postNotificationName:S6LibraryDidChangeNotification object:nil];
    }
}

- (void)playerChanged
{
    if (!S6IsPad() && self.playerBar.hidden == [self showsPlayerBar]) {
        [LTTransitionSettings animateWithDuration:0.25 animations:^{ [self.view setNeedsLayout]; [self.view layoutIfNeeded]; }];
    }
}

- (void)playerFailed:(NSNotification *)note
{
    NSError *error = [note.userInfo objectForKey:@"error"];
    if (error.localizedDescription.length) [self showToast:error.localizedDescription];
}

@end
