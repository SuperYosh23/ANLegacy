#import "LTSplitContainerViewController.h"
#import "LTTabBarController.h"
#import "LTGraphics.h"
#import "LTSafeArea.h"
#import "LTPlaylistStore.h"
#import "LTYouTubeClient.h"
#import "LTLocalPlaylistDetailViewController.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kSidebarWidth = 260.0f;
static const CGFloat kSidebarRailWidth = 56.0f;
static const NSUInteger kSidebarPlaylistsTagBase = 1000;

typedef NS_ENUM(NSInteger, LTSidebarMode) {
    LTSidebarModeHidden = 0,
    LTSidebarModeRail,
    LTSidebarModeFull
};

@interface LTSplitContainerViewController ()
@property (nonatomic, strong) LTTabBarController *tabController;
@property (nonatomic, strong) UIView *sidebarView;
@property (nonatomic, strong) UILabel *sidebarTitleLabel;
@property (nonatomic, strong) CALayer *sidebarSeparator;
@property (nonatomic, strong) NSMutableArray *sidebarButtons;
@property (nonatomic, strong) NSMutableArray *sidebarItemTitles;
@property (nonatomic, strong) NSMutableArray *sidebarPlaylistButtons;
@property (nonatomic, strong) UILabel *sidebarPlaylistsHeaderLabel;
@property (nonatomic, strong) UIScrollView *sidebarPlaylistsScrollView;
@property (nonatomic, assign) BOOL landscape;
@property (nonatomic, assign) LTSidebarMode currentMode;

@end

@implementation LTSplitContainerViewController

#pragma mark - Playlists section

// Rows shown beneath the main destinations in full mode. Kept hidden in the
// rail so it never crowds the thin icon strip. With more playlists than fit,
// the section scrolls so all rows stay reachable.
- (void)rebuildPlaylistRows {
    if (!self.sidebarPlaylistsScrollView) {
        UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        scrollView.clipsToBounds = YES;
        scrollView.showsVerticalScrollIndicator = NO;
        scrollView.showsHorizontalScrollIndicator = NO;
        self.sidebarPlaylistsScrollView = scrollView;
        [self.sidebarView addSubview:scrollView];
    }

    if (!self.sidebarPlaylistsHeaderLabel) {
        self.sidebarPlaylistsHeaderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.sidebarPlaylistsHeaderLabel.text = @"PLAYLISTS";
        self.sidebarPlaylistsHeaderLabel.font = [UIFont boldSystemFontOfSize:11.0f];
        self.sidebarPlaylistsHeaderLabel.textColor = [UIColor colorWithWhite:0.55f alpha:1.0f];
        [self.sidebarPlaylistsScrollView addSubview:self.sidebarPlaylistsHeaderLabel];
    }

    for (UIButton *button in self.sidebarPlaylistButtons) {
        [button removeFromSuperview];
    }
    [self.sidebarPlaylistButtons removeAllObjects];

    NSArray *playlists = [[LTPlaylistStore sharedStore] playlists];
    NSUInteger index = 0;
    for (LTLocalPlaylist *playlist in playlists) {
        UIButton *button = [self makeSidebarButtonWithTitle:[playlist name]
                                                       glyph:0xF5FD
                                                       index:(NSUInteger)kSidebarPlaylistsTagBase + index];
        UIImage *cover = [self playlistCoverImageForPlaylist:playlist];
        if (cover) {
            [button setImage:cover forState:UIControlStateNormal];
            [button setImage:cover forState:UIControlStateSelected];
        } else {
            [self loadPlaylistThumbnail:playlist intoButton:button];
        }
        [self.sidebarPlaylistsScrollView addSubview:button];
        [self.sidebarPlaylistButtons addObject:button];
        index++;
    }
}

// Small rounded thumbnail of the playlist cover for the sidebar row; nil when
// the playlist has no art (the glyph fallback from makeSidebarButton stays).
- (UIImage *)playlistCoverImageForPlaylist:(LTLocalPlaylist *)playlist {
    if (!playlist.coverPath.length) return nil;
    return [self styledSidebarThumbnail:[UIImage imageWithContentsOfFile:playlist.coverPath]];
}

// Mirrors the library grid's fallback: playlists without user-set cover art
// show their first track's thumbnail, so the sidebar row matches what the
// library already displays. The glyph stays until the image arrives.
- (void)loadPlaylistThumbnail:(LTLocalPlaylist *)playlist intoButton:(UIButton *)button {
    if (!playlist.tracks.count) return;
    LTTrack *first = [playlist.tracks objectAtIndex:0];
    if (!first.thumbnailURL.length) return;
    NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:first.thumbnailURL];
    __weak UIButton *weakButton = button;
    [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
        UIImage *thumb = [self styledSidebarThumbnail:image];
        if (!thumb) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIButton *target = weakButton;
            if (target) {
                [target setImage:thumb forState:UIControlStateNormal];
                [target setImage:thumb forState:UIControlStateSelected];
            }
        });
    }];
}

- (UIImage *)styledSidebarThumbnail:(UIImage *)image {
    if (!image) return nil;
    CGFloat size = 24.0f;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0f, 0.0f, size, size)
                                                    cornerRadius:4.0f];
    [path addClip];
    CGFloat minScale = MAX(size / image.size.width, size / image.size.height);
    CGFloat scaledW = image.size.width * minScale;
    CGFloat scaledH = image.size.height * minScale;
    [image drawInRect:CGRectMake((size - scaledW) / 2.0f, (size - scaledH) / 2.0f, scaledW, scaledH)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)playlistsDidChange:(NSNotification *)notification {
    [self rebuildPlaylistRows];
    [self layoutChildrenAnimated:YES];
}

+ (BOOL)isSupported {
    return ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
}

- (instancetype)initWithTabController:(LTTabBarController *)tabController {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _tabController = tabController;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    [self addChildViewController:self.tabController];
    [self.view addSubview:self.tabController.view];
    [self.tabController didMoveToParentViewController:self];

    [self buildSidebar];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playlistsDidChange:)
                                                 name:LTPlaylistsDidChangeNotification
                                               object:nil];

    __weak LTSplitContainerViewController *weakSelf = self;
    self.tabController.selectionDidChange = ^(NSInteger index) {
        __strong LTSplitContainerViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf setSidebarSelection:index];
        [strongSelf layoutChildrenAnimated:YES];
    };

    [self layoutChildrenAnimated:NO];
    [self setSidebarSelection:(NSInteger)self.tabController.selectedIndex];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutChildrenAnimated:NO];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self layoutChildrenAnimated:NO];
    } completion:nil];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate {
    return YES;
}

#pragma mark - Sidebar

- (UIColor *)accentColor {
    return [UIColor colorWithRed:0.35f green:0.68f blue:1.0f alpha:1.0f];
}

- (void)buildSidebar {
    self.sidebarView = [[UIView alloc] initWithFrame:CGRectZero];
    self.sidebarView.backgroundColor = [UIColor colorWithWhite:0.09f alpha:1.0f];
    [self.view addSubview:self.sidebarView];

    self.sidebarSeparator = [CALayer layer];
    self.sidebarSeparator.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f].CGColor;
    [self.sidebarView.layer addSublayer:self.sidebarSeparator];

    self.sidebarTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.sidebarTitleLabel.text = @"audioNINJA Legacy";
    self.sidebarTitleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.sidebarTitleLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
    self.sidebarTitleLabel.backgroundColor = [UIColor clearColor];
    self.sidebarTitleLabel.textAlignment = NSTextAlignmentLeft;
    [self.sidebarView addSubview:self.sidebarTitleLabel];

    NSArray *items = @[
        @{ @"title": @"Home",        @"glyph": @(0xF015) },
        @{ @"title": @"Search",      @"glyph": @(0xF002) },
        @{ @"title": @"Library",     @"glyph": @(0xF5FD) },
        @{ @"title": @"Settings",    @"glyph": @(0xF013) },
        @{ @"title": @"Now Playing", @"glyph": @(0xF04B) },
    ];

    self.sidebarButtons = [NSMutableArray array];
    self.sidebarItemTitles = [NSMutableArray array];
    self.sidebarPlaylistButtons = [NSMutableArray array];
    for (NSUInteger i = 0; i < items.count; i++) {
        NSDictionary *item = [items objectAtIndex:i];
        NSString *title = [item objectForKey:@"title"];
        [self.sidebarItemTitles addObject:title];
        UIButton *button = [self makeSidebarButtonWithTitle:title
                                                       glyph:(unichar)[[item objectForKey:@"glyph"] unsignedShortValue]
                                                        index:i];
        [self.sidebarView addSubview:button];
        [self.sidebarButtons addObject:button];
    }

    [self rebuildPlaylistRows];
}

- (UIImage *)sidebarIconImage:(unichar)glyph tint:(UIColor *)color {
    UIImage *image = [LTGraphics glyphIcon:glyph size:20.0f color:color];
    if (image) return image;
    UIImage *fallback = nil;
    switch (glyph) {
        case 0xF015: fallback = [LTGraphics homeIcon]; break;
        case 0xF002: fallback = [LTGraphics searchIcon]; break;
        case 0xF5FD: fallback = [LTGraphics libraryIcon]; break;
        case 0xF013: fallback = [LTGraphics settingsIcon]; break;
        default: break;
    }
    if (!fallback) return nil;
    return fallback;
}

- (UIFont *)niceSidebarFont {
    if ([UIFont respondsToSelector:@selector(systemFontOfSize:weight:)]) {
        return [UIFont systemFontOfSize:15.0f weight:UIFontWeightSemibold];
    }
    return [UIFont boldSystemFontOfSize:15.0f];
}

- (UIButton *)makeSidebarButtonWithTitle:(NSString *)title glyph:(unichar)glyph index:(NSUInteger)index {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = (NSInteger)index;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.titleLabel.font = [self niceSidebarFont];
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    UIColor *normalColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    UIColor *selectedColor = [self accentColor];

    UIImage *normalIcon = [self sidebarIconImage:glyph tint:normalColor];
    UIImage *templateIcon = [[self sidebarIconImage:glyph tint:selectedColor] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [button setImage:normalIcon forState:UIControlStateNormal];
    [button setImage:templateIcon forState:UIControlStateSelected];
    button.imageView.tintColor = selectedColor;
    button.tintColor = selectedColor;

    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:normalColor forState:UIControlStateNormal];
    [button setTitleColor:selectedColor forState:UIControlStateSelected];

    button.imageEdgeInsets = UIEdgeInsetsMake(0.0f, 18.0f, 0.0f, 0.0f);
    button.titleEdgeInsets = UIEdgeInsetsMake(0.0f, 24.0f, 0.0f, 0.0f);

    [button setBackgroundImage:[self selectedPillImage] forState:UIControlStateSelected];

    [button addTarget:self action:@selector(sidebarTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIImage *)selectedPillImage {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(220.0f, 46.0f), NO, 0.0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0f, 0.0f, 220.0f, 46.0f)
                                                    cornerRadius:11.0f];
    [[UIColor colorWithWhite:1.0f alpha:0.12f] setFill];
    [path fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (void)sidebarTapped:(UIButton *)button {
    NSInteger index = button.tag;
    if (index >= 0 && index < (NSInteger)self.tabController.viewControllers.count) {
        // Main destination: switching also triggers the animated sidebar
        // relayout via the tab controller's selection announcement.
        self.tabController.selectedIndex = index;
        [self setSidebarSelection:index];
        return;
    }
    // Playlist row: open the playlist's detail screen on the current stack.
    NSUInteger playlistIndex = (NSUInteger)(button.tag - kSidebarPlaylistsTagBase);
    NSArray *playlists = [[LTPlaylistStore sharedStore] playlists];
    if (playlistIndex >= playlists.count) return;
    LTLocalPlaylist *playlist = [playlists objectAtIndex:playlistIndex];
    LTLocalPlaylistDetailViewController *detail = [[LTLocalPlaylistDetailViewController alloc] initWithPlaylist:playlist];
    UINavigationController *nav = (UINavigationController *)self.tabController.selectedViewController;
    if ([nav isKindOfClass:[UINavigationController class]]) {
        [nav pushViewController:detail animated:YES];
    }
}

- (void)setSidebarSelection:(NSInteger)index {
    for (UIButton *button in self.sidebarButtons) {
        button.selected = (button.tag == index);
    }
}

#pragma mark - Layout

- (BOOL)isLandscape {
    CGRect b = self.view.bounds;
    return (b.size.width > b.size.height);
}

- (CGFloat)statusBarHeight {
    CGFloat h = CGRectGetHeight([UIApplication sharedApplication].statusBarFrame);
    if (h < 1.0f) h = 20.0f;
    return h;
}

- (void)layoutChildrenAnimated:(BOOL)animated {
    CGRect b = self.view.bounds;
    if (b.size.width < 1.0f || b.size.height < 1.0f) return;
    BOOL landscape = [self isLandscape];
    LTSidebarMode mode = LTSidebarModeHidden;
    if (landscape) {
        // Now Playing is a distraction-free rail; every other destination gets
        // the full sidebar.
        BOOL nowPlaying = (self.tabController.selectedIndex == (NSInteger)(self.tabController.viewControllers.count - 1));
        mode = nowPlaying ? LTSidebarModeRail : LTSidebarModeFull;
    }
    CGFloat sideW = (mode == LTSidebarModeHidden) ? 0.0f
                  : (mode == LTSidebarModeRail) ? kSidebarRailWidth
                  : kSidebarWidth;

    BOOL modeChanged = (mode != self.currentMode);

    void (^updates)(void) = ^{
        self.sidebarView.frame = CGRectMake(0.0f, 0.0f, sideW, b.size.height);
        self.sidebarView.hidden = (mode == LTSidebarModeHidden);
        self.tabController.view.frame = CGRectMake(sideW, 0.0f, b.size.width - sideW, b.size.height);
        self.tabController.tabBarForcedHidden = (mode != LTSidebarModeHidden);
        [self layoutTabBarHidden:(mode != LTSidebarModeHidden) inBounds:b];
        [self layoutSidebarItemsForMode:mode height:b.size.height];
    };
    if (animated && (modeChanged || self.landscape != landscape)) {
        // Soften the rail/full swap: the width walks with a gentle ease while
        // title, separator, and rows crossfade. layoutSidebarItemsForMode:
        // snaps the `hidden` flags to the destination state, which would kill
        // the fade, so visibility is restored up front and rows are only hidden
        // after the fade-out actually completes.
        [UIView animateWithDuration:0.32f
                              delay:0.0f
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:updates
                         completion:nil];
        BOOL toRail = (mode == LTSidebarModeRail);
        CGFloat toAlpha = toRail ? 0.0f : 1.0f;
        self.sidebarTitleLabel.hidden = NO;
        self.sidebarSeparator.hidden = NO;
        self.sidebarPlaylistsScrollView.hidden = NO;
        for (UIButton *button in self.sidebarPlaylistButtons) {
            button.hidden = NO;
        }
        if (!toRail) {
            self.sidebarTitleLabel.alpha = 0.0f;
            self.sidebarSeparator.opacity = 0.0f;
            for (UIButton *button in self.sidebarPlaylistButtons) {
                button.alpha = 0.0f;
            }
        }
        [UIView animateWithDuration:0.16f
                              delay:0.08f
                            options:UIViewAnimationOptionCurveEaseIn
                         animations:^{
            self.sidebarTitleLabel.alpha = toAlpha;
            self.sidebarSeparator.opacity = toAlpha;
            for (UIButton *button in self.sidebarPlaylistButtons) {
                button.alpha = toAlpha;
            }
        } completion:^(BOOL finished) {
            if (finished && toRail) {
                self.sidebarTitleLabel.hidden = YES;
                self.sidebarSeparator.hidden = YES;
                self.sidebarPlaylistsScrollView.hidden = YES;
                for (UIButton *button in self.sidebarPlaylistButtons) {
                    button.hidden = YES;
                }
            }
        }];
    } else {
        self.sidebarTitleLabel.alpha = 1.0f;
        self.sidebarSeparator.opacity = 1.0f;
        for (UIButton *button in self.sidebarPlaylistButtons) {
            button.alpha = 1.0f;
        }
        updates();
    }
    self.landscape = landscape;
    self.currentMode = mode;
}

// Hides the tab bar by parking it off the bottom edge and giving the selected
// view controller the freed space. UITabBarController keeps a hidden bar's
// 49pt frame in place (just invisibly), which would otherwise leave a dead
// black strip beneath the player while the bar's side in landscape is unused.
// The bar is collapsed to zero height as well, so every internal
// height - barHeight computation also reserves nothing for it.
- (void)layoutTabBarHidden:(BOOL)hidden inBounds:(CGRect)b {
    UITabBar *tabBar = self.tabController.tabBar;
    CGRect tBounds = self.tabController.view.bounds;
    CGFloat tbH = 49.0f;
    if (hidden) {
        tabBar.frame = CGRectMake(0.0f, tBounds.size.height, tBounds.size.width, 0.0f);
    } else {
        tabBar.frame = CGRectMake(0.0f, tBounds.size.height - tbH, tBounds.size.width, tbH);
    }
    tabBar.hidden = hidden;
    UIViewController *sel = self.tabController.selectedViewController;
    if (sel) {
        sel.view.frame = CGRectMake(0.0f, 0.0f, tBounds.size.width,
                                    tBounds.size.height - (hidden ? 0.0f : tbH));
    }
}

// Positions the title/separator and each row for the current sidebar mode. The
// rail discards the title and separator and gutters the buttons into a thin
// centered-icon strip. Rows keep their vertical anchors so full/rail share the
// same icon heights.
- (void)layoutSidebarItemsForMode:(LTSidebarMode)mode height:(CGFloat)height {
    if (mode == LTSidebarModeHidden) return;
    BOOL rail = (mode == LTSidebarModeRail);
    CGFloat width = rail ? kSidebarRailWidth : kSidebarWidth;
    BOOL showTitle = !rail;

    self.sidebarTitleLabel.hidden = !showTitle;
    self.sidebarSeparator.hidden = !showTitle;

    CGFloat top = [self statusBarHeight] + 12.0f;
    if (showTitle) {
        self.sidebarTitleLabel.frame = CGRectMake(20.0f, top, width - 40.0f, 26.0f);
        self.sidebarSeparator.frame = CGRectMake(0.0f, top + 40.0f, width, 0.5f);
    }

    CGFloat y = top + 58.0f;
    CGFloat rowH = 46.0f;
    CGFloat gap = rail ? 8.0f : 10.0f;
    for (UIButton *button in self.sidebarButtons) {
        [self configureSidebarButton:button rail:rail];
        if (showTitle) {
            button.frame = CGRectMake(14.0f, y, width - 28.0f, rowH);
        } else {
            button.frame = CGRectMake(0.0f, y, width, rowH);
        }
        y += rowH + gap;
    }

    // Playlists live beneath the main destinations in full mode only. The
    // rail is a distraction-free icon strip, so the whole section drops out.
    BOOL showPlaylists = (showTitle && self.sidebarPlaylistButtons.count > 0);
    self.sidebarPlaylistsScrollView.hidden = !showPlaylists;
    self.sidebarPlaylistsHeaderLabel.hidden = !showPlaylists;
    for (UIButton *button in self.sidebarPlaylistButtons) {
        button.hidden = !showPlaylists;
    }
    if (showPlaylists) {
        CGFloat scrollTop = y;
        CGFloat contentW = width;
        self.sidebarPlaylistsScrollView.frame = CGRectMake(0.0f, scrollTop, width, height - scrollTop);
        self.sidebarPlaylistsHeaderLabel.frame = CGRectMake(20.0f, 6.0f, contentW - 40.0f, 18.0f);
        CGFloat ry = 32.0f;
        for (UIButton *button in self.sidebarPlaylistButtons) {
            [self configureSidebarButton:button rail:NO];
            button.frame = CGRectMake(14.0f, ry, contentW - 28.0f, rowH);
            ry += rowH + gap;
        }
        CGRect frame = self.sidebarPlaylistsScrollView.frame;
        self.sidebarPlaylistsScrollView.contentSize = CGSizeMake(contentW, ry);
        self.sidebarPlaylistsScrollView.alwaysBounceVertical = (ry > frame.size.height);
    }
}

// Swaps a row between full (icon + label + pill) and rail (centered icon only)
// presentation. Detects the current state from the button's own title so it is
// cheap to run on every layout pass.
- (void)configureSidebarButton:(UIButton *)button rail:(BOOL)rail {
    BOOL currentlyRail = ([button titleForState:UIControlStateNormal].length == 0);
    if (currentlyRail == rail) return;
    if (rail) {
        [button setTitle:nil forState:UIControlStateNormal];
        [button setTitle:nil forState:UIControlStateSelected];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        button.imageEdgeInsets = UIEdgeInsetsZero;
        button.titleEdgeInsets = UIEdgeInsetsZero;
        [button setBackgroundImage:nil forState:UIControlStateSelected];
    } else {
        NSUInteger i = [self.sidebarButtons indexOfObject:button];
        if (i < self.sidebarItemTitles.count) {
            NSString *title = [self.sidebarItemTitles objectAtIndex:i];
            [button setTitle:title forState:UIControlStateNormal];
            [button setTitle:title forState:UIControlStateSelected];
        }
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.imageEdgeInsets = UIEdgeInsetsMake(0.0f, 18.0f, 0.0f, 0.0f);
        button.titleEdgeInsets = UIEdgeInsetsMake(0.0f, 24.0f, 0.0f, 0.0f);
        [button setBackgroundImage:[self selectedPillImage] forState:UIControlStateSelected];
    }
}

@end