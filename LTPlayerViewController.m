#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <sys/utsname.h>
#import "LTPlayerViewController.h"
#import "LTPlayerController.h"
#import "LTQueueViewController.h"
#import "LTYouTubeClient.h"
#import "LTPlaylistStore.h"
#import "LTGraphics.h"
#import "LTDebugSettings.h"
#import "LTOneHandedMode.h"
#import "LTLog.h"
#import "LTSafeArea.h"
#import "LTSimpleCell.h"
#import "LTHaptics.h"

static BOOL sHasShownSwipeHint = NO;

@interface LTPlayerViewController () <UIScrollViewDelegate, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIPanGestureRecognizer *swipePan;
@property (nonatomic, strong) UIPanGestureRecognizer *mainVerticalPan;
@property (nonatomic, strong) UIPanGestureRecognizer *queueDrag;
@property (nonatomic, strong) UIPanGestureRecognizer *statsDrag;
@property (nonatomic, strong) UIView *mainPane;
@property (nonatomic, strong) UIView *queuePane;
@property (nonatomic, strong) UIView *statsPane;
@property (nonatomic, strong) UIView *queueHandle;
@property (nonatomic, strong) UIView *statsHandle;
@property (nonatomic, strong) UILabel *queueHeader;
@property (nonatomic, strong) UITableView *queueTable;
@property (nonatomic, strong) UILabel *lyricsTitle;
@property (nonatomic, strong) UIScrollView *lyricsScroll;
@property (nonatomic, strong) NSMutableArray *lyricLabelViews;
@property (nonatomic, copy) NSArray *lyricLines;
@property (nonatomic, assign) NSInteger activeLyricIndex;
@property (nonatomic, copy) NSString *lyricsVideoId;
@property (nonatomic, strong) UILabel *pagesHint;
@property (nonatomic, assign) BOOL queueDrawerOpen;
@property (nonatomic, assign) BOOL statsDrawerOpen;
@property (nonatomic, assign) BOOL draggingDrawer;
@property (nonatomic, assign) NSInteger activeDragIndex;
@property (nonatomic, assign) BOOL dragIndexResolved;
@property (nonatomic, assign) CGFloat drawerDragStartY;
@property (nonatomic, assign) CGFloat drawerDragStartX;
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) UIView *scrimView;
// One white pill behind the whole five-button transport row, used only in the
// layouts that are neither iPad nor a notched phone. The others keep a disc
// behind each key.
@property (nonatomic, strong) UIView *transportBar;
// Soft halo shown behind whichever transport key is being held down. Kept as a
// sibling view rather than a layer shadow because the keys clip to bounds for
// their rounded backgrounds, which would cut a shadow off at the edge.
@property (nonatomic, strong) UIView *pressGlow;
@property (nonatomic, strong) NSCache *blurCache;
@property (nonatomic, strong) NSCache *paletteCache;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UIImageView *incomingArtworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UILabel *sourceLabel;
@property (nonatomic, strong) UILabel *bitrateLabel;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSTimer *lyricsTimer;
@property (nonatomic, strong) NSTimer *swipeHintTimer;
@property (nonatomic, assign) BOOL showingSwipeHint;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) BOOL panning;
@property (nonatomic, assign) CGPoint artworkRestingCenter;
@property (nonatomic, assign) CGFloat panBaseX;
@property (nonatomic, assign) BOOL panCommitted;
@property (nonatomic, assign) NSInteger panSwipeDir;
@property (nonatomic, assign) NSInteger lastGlyphMode;
@property (nonatomic, assign) CGFloat lastDebugPW;
@property (nonatomic, assign) CGFloat lastDebugPH;
@property (nonatomic, assign) BOOL lastDebugDock;
@end

@implementation LTPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Now Playing";
    self.view.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
    // The queue/stats drawers slide in from the edges. Without clipping their
    // closed frames (which sit just outside the view) would render over the
    // tab bar / navigation chrome.
    self.view.clipsToBounds = YES;
    LTLog(@"PLAYER_VC bounds=%d x %d screenH=%d tall=%d",
          (int)self.view.bounds.size.width, (int)self.view.bounds.size.height,
          (int)[[UIScreen mainScreen] bounds].size.height, (int)[self isTallScreen]);

    self.blurCache = [[NSCache alloc] init];
    self.paletteCache = [[NSCache alloc] init];
    [self applyArtworkBackgroundPref];

    // Main pane is always full-screen. Queue and stats are overlay drawers that
    // slide in from the top and bottom edges over the main pane.
    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    CGFloat drawerH = [self drawerHeight];

    self.mainPane = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    self.mainPane.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.mainPane];

    self.queuePane = [[UIView alloc] initWithFrame:CGRectMake(0, -drawerH, W, drawerH)];
    self.queuePane.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.97f];
    self.queuePane.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.queuePane];

    self.statsPane = [[UIView alloc] initWithFrame:CGRectMake(0, H, W, drawerH)];
    self.statsPane.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.97f];
    self.statsPane.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.statsPane];

    self.queueDrawerOpen = NO;
    self.statsDrawerOpen = NO;

    self.incomingArtworkView = [[UIImageView alloc] init];
    self.incomingArtworkView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    self.incomingArtworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.incomingArtworkView.clipsToBounds = YES;
    self.incomingArtworkView.alpha = 0.0f;
    [self.mainPane addSubview:self.incomingArtworkView];

    self.artworkView = [[UIImageView alloc] init];
    self.artworkView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.userInteractionEnabled = NO;
    [self.mainPane addSubview:self.artworkView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [self.mainPane addSubview:self.spinner];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [self.mainPane addSubview:self.titleLabel];

    self.artistLabel = [[UILabel alloc] init];
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.font = [UIFont systemFontOfSize:13];
    self.artistLabel.textColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    self.artistLabel.backgroundColor = [UIColor clearColor];
    [self.mainPane addSubview:self.artistLabel];

    self.sourceLabel = [[UILabel alloc] init];
    self.sourceLabel.textAlignment = NSTextAlignmentLeft;
    self.sourceLabel.font = [UIFont boldSystemFontOfSize:17];
    self.sourceLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    self.sourceLabel.backgroundColor = [UIColor clearColor];
    self.sourceLabel.text = @"";
    [self.mainPane addSubview:self.sourceLabel];

    self.bitrateLabel = [[UILabel alloc] init];
    self.bitrateLabel.textAlignment = NSTextAlignmentLeft;
    self.bitrateLabel.font = [UIFont systemFontOfSize:11];
    self.bitrateLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
    self.bitrateLabel.backgroundColor = [UIColor clearColor];
    self.bitrateLabel.text = @"";
    [self.mainPane addSubview:self.bitrateLabel];

    self.elapsedLabel = [[UILabel alloc] init];
    self.elapsedLabel.font = [UIFont systemFontOfSize:11];
    self.elapsedLabel.textColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    self.elapsedLabel.backgroundColor = [UIColor clearColor];
    self.elapsedLabel.text = @"0:00";
    [self.mainPane addSubview:self.elapsedLabel];

    self.remainingLabel = [[UILabel alloc] init];
    self.remainingLabel.font = [UIFont systemFontOfSize:11];
    self.remainingLabel.textColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    self.remainingLabel.backgroundColor = [UIColor clearColor];
    self.remainingLabel.textAlignment = NSTextAlignmentRight;
    self.remainingLabel.text = @"0:00";
    [self.mainPane addSubview:self.remainingLabel];

    self.progressSlider = [[UISlider alloc] init];
    [self.progressSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchedUp:) forControlEvents:UIControlEventTouchUpInside];
    [self.progressSlider addTarget:self action:@selector(sliderTouchedUp:) forControlEvents:UIControlEventTouchUpOutside];
    [self.mainPane addSubview:self.progressSlider];

    self.prevButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.prevButton setImage:[UIImage imageNamed:@"IcoPrev"] forState:UIControlStateNormal];
    [self.prevButton addTarget:self action:@selector(prevTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPane addSubview:self.prevButton];

    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.playButton setImage:[UIImage imageNamed:@"IcoPlay"] forState:UIControlStateNormal];
    [self.playButton addTarget:self action:@selector(playTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPane addSubview:self.playButton];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.nextButton setImage:[UIImage imageNamed:@"IcoNext"] forState:UIControlStateNormal];
    [self.nextButton addTarget:self action:@selector(nextTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPane addSubview:self.nextButton];

    self.shuffleButton = [self makeIconButton:@"IcoShuffle" selectedImage:@"IcoShuffleBlue" action:@selector(shuffleTapped:)];
    [self.mainPane addSubview:self.shuffleButton];

    self.repeatButton = [self makeIconButton:@"IcoRepeat" selectedImage:@"IcoRepeatBlue" action:@selector(repeatTapped:)];
    [self.mainPane addSubview:self.repeatButton];

    // Sits under every transport key, so the glyphs stay crisp on top of it.
    self.transportBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.transportBar.backgroundColor = [UIColor whiteColor];
    self.transportBar.userInteractionEnabled = NO; // taps go to the buttons
    self.transportBar.hidden = YES;
    [self.mainPane insertSubview:self.transportBar belowSubview:self.prevButton];

    // Halo for the held key. A soft accent tint rather than white, because the
    // row is already a white pill and a white glow on white would be invisible.
    self.pressGlow = [[UIView alloc] initWithFrame:CGRectZero];
    self.pressGlow.backgroundColor = [UIColor colorWithRed:0.42f green:0.62f blue:0.95f alpha:0.30f];
    self.pressGlow.userInteractionEnabled = NO;
    self.pressGlow.hidden = YES;
    [self.mainPane insertSubview:self.pressGlow belowSubview:self.prevButton];

    for (UIButton *key in [NSArray arrayWithObjects:self.shuffleButton, self.prevButton,
                           self.playButton, self.nextButton, self.repeatButton, nil]) {
        [self addPressFeedbackToButton:key];
    }

    self.pagesHint = [[UILabel alloc] init];
    self.pagesHint.text = @"Swipe down for queue   \u00B7   Swipe up for lyrics";
    self.pagesHint.textAlignment = NSTextAlignmentCenter;
    self.pagesHint.font = [UIFont boldSystemFontOfSize:12];
    self.pagesHint.textColor = [UIColor colorWithWhite:0.85f alpha:0.85f];
    self.pagesHint.backgroundColor = [UIColor clearColor];
    self.pagesHint.hidden = YES;
    [self.mainPane addSubview:self.pagesHint];

    [self layoutControls];
    [self buildQueuePane];
    [self buildStatsPane];
    [self layoutPages];
    [self setupSwipeGestures];
    [self applyTransportImages];
    self.lastGlyphMode = NSNotFound;
}

- (void)setupSwipeGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.minimumNumberOfTouches = 1;
    pan.delegate = self;
    self.swipePan = pan;
    [self.mainPane addGestureRecognizer:pan];

    self.mainVerticalPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mainVerticalPan:)];
    self.mainVerticalPan.delegate = self;
    self.mainVerticalPan.cancelsTouchesInView = NO;
    [self.mainPane addGestureRecognizer:self.mainVerticalPan];

    self.queueDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drawerDragged:)];
    self.queueDrag.delegate = self;
    [self.queuePane addGestureRecognizer:self.queueDrag];

    self.statsDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drawerDragged:)];
    self.statsDrag.delegate = self;
    [self.statsPane addGestureRecognizer:self.statsDrag];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    BOOL dock = [self isDockMode];
    if (gestureRecognizer == self.swipePan) {
        // In dock mode the horizontal axis belongs to the side drawers; the
        // artwork swipe (track-changing) switches off in favour of the buttons.
        if (dock) return NO;
        CGPoint v = [self.swipePan velocityInView:self.mainPane];
        return fabs(v.x) > fabs(v.y);
    }
    if (gestureRecognizer == self.mainVerticalPan) {
        CGPoint v = [self.mainVerticalPan velocityInView:self.mainPane];
        if (dock) return fabs(v.x) > fabs(v.y);
        return fabs(v.y) > fabs(v.x);
    }
    if (gestureRecognizer == self.queueDrag || gestureRecognizer == self.statsDrag) {
        CGPoint v = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
        if (dock) return fabs(v.x) >= fabs(v.y);
        return fabs(v.y) >= fabs(v.x);
    }
    return YES;
}

// Drawer drags must only start outside the scrollable middle region, so the
// queue table / lyrics scroll keep their normal scrolling. Touches on the handle
// strips and empty drawer margins move the drawer instead.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.queueDrag && self.queueTable) {
        CGPoint p = [touch locationInView:self.queueTable];
        return !CGRectContainsPoint(self.queueTable.bounds, p);
    }
    if (gestureRecognizer == self.statsDrag && self.lyricsScroll) {
        CGPoint p = [touch locationInView:self.lyricsScroll];
        return !CGRectContainsPoint(self.lyricsScroll.bounds, p);
    }
    return YES;
}

- (CGFloat)drawerHeight {
    CGFloat h = self.view.bounds.size.height;
    CGFloat drawerH = floorf(h * 0.70f);
    if (drawerH < 120.0f) drawerH = h;
    return drawerH;
}

// In dock mode the drawers slide in from the sides, so they take a width.
- (CGFloat)drawerWidth {
    CGFloat w = self.view.bounds.size.width;
    CGFloat dw = floorf(w * 0.50f);
    if (dw > 340.0f) dw = 340.0f;
    if (dw < 220.0f) dw = 220.0f;
    return dw;
}

- (void)queueHandleTapped:(UITapGestureRecognizer *)tap {
    [self setQueueDrawerOpen:NO animated:YES];
}

- (void)statsHandleTapped:(UITapGestureRecognizer *)tap {
    [self setStatsDrawerOpen:NO animated:YES];
}

// Slides one drawer to its open or closed resting position. Shared by the tap
// handlers and by the end of a drag, so both land on exactly the same frame.
- (void)slideDrawerAtIndex:(NSInteger)index open:(BOOL)open animated:(BOOL)animated {
    UIView *drawer = (index == 0) ? self.queuePane : self.statsPane;
    CGRect target;
    if ([self isDockMode]) {
        CGFloat w = self.view.bounds.size.width;
        CGFloat dw = [self drawerWidth];
        CGFloat x = (index == 0) ? (open ? 0.0f : -dw) : (open ? (w - dw) : w);
        target = CGRectMake(x, 0.0f, dw, self.view.bounds.size.height);
    } else {
        CGFloat h = self.view.bounds.size.height;
        CGFloat drawerH = [self drawerHeight];
        CGFloat y = (index == 0) ? (open ? 0.0f : -drawerH) : (open ? (h - drawerH) : h);
        target = CGRectMake(0.0f, y, self.view.bounds.size.width, drawerH);
    }
    // Plain curve-based animation: -animateWithDuration:delay:options: is the
    // only variant that exists on iOS 6, and the spring API would need guarding.
    if (animated) {
        [UIView animateWithDuration:0.25f
                              delay:0.0
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ drawer.frame = target; }
                         completion:nil];
    } else {
        drawer.frame = target;
    }
}

// The drawers are mutually exclusive, so opening one closes the other.
- (void)setQueueDrawerOpen:(BOOL)open animated:(BOOL)animated {
    if (open && self.statsDrawerOpen) {
        [self setStatsDrawerOpen:NO animated:animated];
    }
    if (_queueDrawerOpen != open) {
        _queueDrawerOpen = open;
        self.draggingDrawer = NO;
        [self slideDrawerAtIndex:0 open:open animated:animated];
    }
    [self layoutPages];
}

- (void)setStatsDrawerOpen:(BOOL)open animated:(BOOL)animated {
    if (open && self.queueDrawerOpen) {
        [self setQueueDrawerOpen:NO animated:animated];
    }
    if (_statsDrawerOpen != open) {
        _statsDrawerOpen = open;
        self.draggingDrawer = NO;
        [self slideDrawerAtIndex:1 open:open animated:animated];
        [self syncLyricsTimer];
    }
    [self layoutPages];
}

#pragma mark - Interactive drawer dragging

// A drag can come from a drawer's own handle pan or from a vertical pan on the
// main view; both drive the same interactive slide.
- (void)beginDrawerDragAtIndex:(NSInteger)index {
    self.activeDragIndex = index;
    self.draggingDrawer = YES;
    UIView *drawer = (index == 0) ? self.queuePane : self.statsPane;
    self.drawerDragStartY = drawer.frame.origin.y;
    self.drawerDragStartX = drawer.frame.origin.x;
}

- (void)updateDrawerDragWithTranslation:(CGFloat)t {
    BOOL isQueue = (self.activeDragIndex == 0);
    UIView *drawer = isQueue ? self.queuePane : self.statsPane;
    if ([self isDockMode]) {
        CGFloat w = self.view.bounds.size.width;
        CGFloat dw = [self drawerWidth];
        CGFloat minX = isQueue ? -dw : (w - dw);
        CGFloat maxX = isQueue ? 0.0f : w;
        CGFloat x = self.drawerDragStartX + t;
        if (x < minX) x = minX + (x - minX) * 0.35f;
        if (x > maxX) x = maxX + (x - maxX) * 0.35f;
        drawer.frame = CGRectMake(x, 0.0f, dw, self.view.bounds.size.height);
        return;
    }
    CGFloat h = self.view.bounds.size.height;
    CGFloat drawerH = [self drawerHeight];
    CGFloat minY = isQueue ? -drawerH : (h - drawerH);
    CGFloat maxY = isQueue ? 0.0f : h;
    CGFloat y = self.drawerDragStartY + t;
    if (y < minY) y = minY + (y - minY) * 0.35f;
    if (y > maxY) y = maxY + (y - maxY) * 0.35f;
    drawer.frame = CGRectMake(0, y, drawer.frame.size.width, drawerH);
}

- (void)endDrawerDragWithVelocity:(CGFloat)v {
    BOOL isQueue = (self.activeDragIndex == 0);
    UIView *drawer = isQueue ? self.queuePane : self.statsPane;
    self.draggingDrawer = NO;
    BOOL open;
    if ([self isDockMode]) {
        CGFloat w = self.view.bounds.size.width;
        CGFloat dw = [self drawerWidth];
        CGFloat openPos = isQueue ? 0.0f : (w - dw);
        CGFloat closedPos = isQueue ? -dw : w;
        CGFloat projected = drawer.frame.origin.x + v * 0.15f;
        if (isQueue) {
            open = projected > closedPos + (openPos - closedPos) * 0.5f;
        } else {
            open = projected < closedPos + (openPos - closedPos) * 0.5f;
        }
    } else {
        CGFloat h = self.view.bounds.size.height;
        CGFloat drawerH = [self drawerHeight];
        CGFloat openPos = isQueue ? 0.0f : (h - drawerH);
        CGFloat closedPos = isQueue ? -drawerH : h;
        CGFloat projected = drawer.frame.origin.y + v * 0.15f;
        if (isQueue) {
            open = projected > closedPos + (openPos - closedPos) * 0.5f;
        } else {
            open = projected < closedPos + (openPos - closedPos) * 0.5f;
        }
    }
    if (isQueue) {
        [self setQueueDrawerOpen:open animated:YES];
    } else {
        [self setStatsDrawerOpen:open animated:YES];
    }
}

- (void)drawerDragged:(UIPanGestureRecognizer *)pan {
    NSInteger index = (pan == self.queueDrag) ? 0 : 1;
    BOOL dock = [self isDockMode];
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            [self beginDrawerDragAtIndex:index];
            break;
        case UIGestureRecognizerStateChanged: {
            CGPoint tr = [pan translationInView:self.view];
            [self updateDrawerDragWithTranslation:dock ? tr.x : tr.y];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            CGPoint ve = [pan velocityInView:self.view];
            [self endDrawerDragWithVelocity:dock ? ve.x : ve.y];
            break;
        }
        default:
            break;
    }
}

// Drag anywhere on the now-playing view: pulls a drawer in from the matching
// edge (vertical in portrait, horizontal in dock), or pushes an already-open
// drawer back out.
- (void)mainVerticalPan:(UIPanGestureRecognizer *)pan {
    BOOL dock = [self isDockMode];
    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            self.dragIndexResolved = NO;
            if (self.queueDrawerOpen) {
                [self beginDrawerDragAtIndex:0];
                self.dragIndexResolved = YES;
            } else if (self.statsDrawerOpen) {
                [self beginDrawerDragAtIndex:1];
                self.dragIndexResolved = YES;
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGPoint tr = [pan translationInView:self.view];
            CGFloat t = dock ? tr.x : tr.y;
            if (!self.dragIndexResolved) {
                if (fabs(t) < 8.0f) break;
                [self beginDrawerDragAtIndex:(t > 0.0f) ? 0 : 1];
                self.dragIndexResolved = YES;
            }
            [self updateDrawerDragWithTranslation:t];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            if (self.dragIndexResolved) {
                CGPoint ve = [pan velocityInView:self.view];
                [self endDrawerDragWithVelocity:dock ? ve.x : ve.y];
            }
            self.dragIndexResolved = NO;
            break;
        }
        default:
            break;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = self.view;
    CGPoint translation = [pan translationInView:view];
    CGFloat width = view.bounds.size.width;
    // On iPad side-by-side the artwork lives in its own left column, so the
    // swipe spans that column rather than the whole screen.
    CGFloat dragSpan = [self isSideBySide] ? self.artworkView.bounds.size.width : width;
    CGFloat maxDrag = dragSpan * 0.5f;

    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            self.panning = YES;
            self.artworkRestingCenter = self.artworkView.center;
            self.panBaseX = self.artworkRestingCenter.x;
            self.panCommitted = NO;
            self.panSwipeDir = 0;
            break;
        }
        case UIGestureRecognizerStateChanged: {
            CGFloat tx = translation.x;
            CGFloat ax = fabs(tx), ay = fabs(translation.y);
            if (ay > ax * 1.5f && ax < 12.0f) break;
            if (tx != 0.0f) self.panSwipeDir = (tx > 0) ? 1 : -1;
            if (self.panSwipeDir != 0 && !self.incomingArtworkView.image) {
                [self prepareIncomingArtForDirection:self.panSwipeDir];
            }

            CGFloat clamped = MAX(-maxDrag, MIN(maxDrag, tx));
            CGFloat progress = fabs(clamped) / maxDrag;

            self.artworkView.center = CGPointMake(self.panBaseX + clamped, self.artworkView.center.y);
            CGFloat scale = 1.0f - progress * 0.15f;
            self.artworkView.transform = CGAffineTransformMakeScale(scale, scale);
            self.artworkView.alpha = 1.0f - progress * 0.35f;

            if (self.panSwipeDir < 0) {
                self.incomingArtworkView.center = CGPointMake(self.panBaseX + maxDrag + (clamped + maxDrag), self.artworkView.center.y);
            } else if (self.panSwipeDir > 0) {
                self.incomingArtworkView.center = CGPointMake(self.panBaseX - maxDrag + (clamped - maxDrag), self.artworkView.center.y);
            }
            self.incomingArtworkView.alpha = progress;
            break;
        }
        case UIGestureRecognizerStateEnded: {
            self.panning = NO;
            CGFloat tx = translation.x + [pan velocityInView:view].x * 0.2f;
            CGFloat velocity = fabs([pan velocityInView:view].x);
            BOOL commit = (fabs(tx) > dragSpan * 0.22f) || velocity > 750.0f;
            if (commit && self.panSwipeDir != 0) {
                self.panCommitted = YES;
                CGFloat dirOff = (self.panSwipeDir > 0) ? 1.0f : -1.0f;
                CGFloat offX = self.panBaseX * dirOff + self.artworkView.bounds.size.width * dirOff;
                [UIView animateWithDuration:0.18f animations:^{
                    self.artworkView.center = CGPointMake(self.panBaseX + offX, self.artworkView.center.y);
                    self.artworkView.alpha = 0.0f;
                    self.artworkView.transform = CGAffineTransformMakeScale(0.9f, 0.9f);
                    self.incomingArtworkView.center = CGPointMake(self.panBaseX, self.artworkView.center.y);
                    self.incomingArtworkView.alpha = 1.0f;
                } completion:^(BOOL finished){
                    if (self.panSwipeDir > 0) {
                        [[LTPlayerController sharedController] previousTrack];
                    } else {
                        [[LTPlayerController sharedController] nextTrack];
                    }
                    // refreshTrack cleared the art while it starts loading the
                    // new track; hand the preview that was sliding in back over
                    // so the area is never blank while the high-res loads.
                    if (self.incomingArtworkView.image) {
                        self.artworkView.image = self.incomingArtworkView.image;
                    }
                    [self resetArtworkPresentation];
                }];
            } else {
                [UIView animateWithDuration:0.22f animations:^{
                    self.artworkView.center = CGPointMake(self.panBaseX, self.artworkView.center.y);
                    self.artworkView.transform = CGAffineTransformIdentity;
                    self.artworkView.alpha = 1.0f;
                    self.incomingArtworkView.alpha = 0.0f;
                    self.incomingArtworkView.center = CGPointMake(self.panBaseX, self.artworkView.center.y);
                }];
            }
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            self.panning = NO;
            [UIView animateWithDuration:0.22f animations:^{
                self.artworkView.center = CGPointMake(self.panBaseX, self.artworkView.center.y);
                self.artworkView.transform = CGAffineTransformIdentity;
                self.artworkView.alpha = 1.0f;
                self.incomingArtworkView.alpha = 0.0f;
                self.incomingArtworkView.center = CGPointMake(self.panBaseX, self.artworkView.center.y);
            }];
            break;
        }
        default:
            break;
    }
}

- (void)prepareIncomingArtForDirection:(NSInteger)dir {
    LTTrack *adj = [[LTPlayerController sharedController] peekTrackOffset:(dir > 0) ? -1 : 1];
    if (!adj || !adj.thumbnailURL.length) {
        self.incomingArtworkView.image = nil;
        return;
    }
    NSString *url = [[LTYouTubeClient sharedClient] highResThumbnailURL:adj.thumbnailURL];
    __weak LTPlayerViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:url completion:^(UIImage *image) {
        if (!image) return;
        LTPlayerViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.panSwipeDir == dir) {
            strongSelf.incomingArtworkView.image = image;
        }
    }];
}

// Restores the artwork (and the incoming preview) to the resting position the
// layout gave them. The base is captured at pan start / layout time, never
// from the live view center: after a commit animation the artwork sits far
// off-screen, so deriving a base from it would park the art out of view.
- (void)resetArtworkPresentation {
    CGPoint resting = self.artworkRestingCenter;
    self.panBaseX = resting.x;
    self.artworkView.center = resting;
    self.artworkView.transform = CGAffineTransformIdentity;
    self.artworkView.alpha = 1.0f;
    self.incomingArtworkView.center = resting;
    self.incomingArtworkView.transform = CGAffineTransformIdentity;
    self.incomingArtworkView.alpha = 0.0f;
    self.incomingArtworkView.image = nil;
    self.spinner.center = resting;
    self.panSwipeDir = 0;
}

- (UIButton *)makeIconButton:(NSString *)imageName selectedImage:(NSString *)selectedImageName action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
    [button setImage:[UIImage imageNamed:selectedImageName] forState:UIControlStateSelected];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// Rings the enlarged transport controls so the floating glyphs read as buttons.
- (void)applyCircleToButton:(UIButton *)button diameter:(CGFloat)diameter {
    if (diameter <= 0.0f) return;
    button.layer.cornerRadius = diameter / 2.0f;
    button.layer.borderWidth = 0.0f;
    button.layer.borderColor = NULL;
    button.layer.backgroundColor = [UIColor whiteColor].CGColor;
    button.clipsToBounds = YES;
}

- (void)removeCircleFromButton:(UIButton *)button {
    button.layer.cornerRadius = 0.0f;
    button.layer.borderWidth = 0.0f;
    button.layer.borderColor = NULL;
    button.layer.backgroundColor = NULL;
}

// Replaces the five white discs with a single pill spanning the row. The glyphs
// are already dark-on-white, so nothing about them changes.
- (void)useTransportBarInRect:(CGRect)row {
    if (!self.transportBar) return;
    [self removeCircleFromButton:self.playButton];
    [self removeCircleFromButton:self.prevButton];
    [self removeCircleFromButton:self.nextButton];
    [self removeCircleFromButton:self.shuffleButton];
    [self removeCircleFromButton:self.repeatButton];
    self.transportBar.frame = row;
    // Height/2 rounds the bar into a pill, so both ends are fully rounded.
    self.transportBar.layer.cornerRadius = row.size.height / 2.0f;
    self.transportBar.hidden = NO;
}

// The iPad and notched-phone layouts keep their per-key discs.
- (void)useTransportCircles {
    if (self.transportBar) self.transportBar.hidden = YES;
}

// A short motor pulse plus a soft halo while a transport key is held, so the
// press is confirmed under the thumb before anything actually happens.
- (void)addPressFeedbackToButton:(UIButton *)button {
    [button addTarget:self action:@selector(transportKeyDown:)
     forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(transportKeyUp:)
     forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(transportKeyUp:)
     forControlEvents:UIControlEventTouchUpOutside];
    [button addTarget:self action:@selector(transportKeyUp:)
     forControlEvents:UIControlEventTouchCancel];
}

- (void)transportKeyDown:(UIButton *)button {
    [LTHaptics pulse];
    if (!self.pressGlow) return;
    CGRect f = button.frame;
    // Inflate so the halo reads as a glow around the key rather than a tint
    // under the glyph. On the disc layouts the key's own white background
    // covers all but this rim, which is exactly what is wanted there.
    CGRect glow = CGRectInset(f, -6.0f, -6.0f);
    self.pressGlow.frame = glow;
    self.pressGlow.layer.cornerRadius = glow.size.height / 2.0f;
    // Re-insert so the halo sits directly under whichever key is held, above
    // the pill.
    [self.mainPane insertSubview:self.pressGlow belowSubview:button];
    self.pressGlow.alpha = 0.0f;
    self.pressGlow.hidden = NO;
    [UIView animateWithDuration:0.08f animations:^{ self.pressGlow.alpha = 1.0f; }];
}

- (void)transportKeyUp:(UIButton *)button {
    if (!self.pressGlow || self.pressGlow.hidden) return;
    [UIView animateWithDuration:0.16f
                     animations:^{ self.pressGlow.alpha = 0.0f; }
                     completion:^(BOOL finished) { self.pressGlow.hidden = YES; }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.backgroundImageView) self.backgroundImageView.frame = self.view.bounds;
    if (self.scrimView) self.scrimView.frame = self.view.bounds;
    [self layoutControls];
    [self layoutPages];
    [self layoutPageSubviews];
    // Glyphs are rendered per layout mode: side-by-side (2), the scaled-up tall
    // layout (1), or the legacy bitmap layout (0). Render on mode change so a
    // portrait→landscape swap swaps the oversized portrait glyphs for the
    // smaller side-by-side ones, without re-rendering on every resize frame.
    NSInteger glyphMode = [self isDockMode] ? 0 : ([self isSideBySide] ? 2 : ([self isTallScreen] ? 1 : 0));
    if (glyphMode != self.lastGlyphMode) {
        [self applyTransportImages];
        self.lastGlyphMode = glyphMode;
    }
    CGFloat pw = self.view.bounds.size.width;
    CGFloat ph = self.view.bounds.size.height;
    BOOL dock = [self isDockMode];
    if (pw != self.lastDebugPW || ph != self.lastDebugPH || dock != self.lastDebugDock) {
        self.lastDebugPW = pw;
        self.lastDebugPH = ph;
        self.lastDebugDock = dock;
        LTLog(@"PLAYER didLayout bounds=%.0fx%.0f dock=%d", pw, ph, dock);
    }
}- (BOOL)isWidescreen {
    // One-handed mode draws the app at the classic 320x480 size, so the player
    // must use the non-widescreen layout even on a large screen.
    if ([LTOneHandedMode isActive]) return NO;
    if ([LTDebugSettings forceNonWidescreen]) return NO;
    if ([LTDebugSettings forceWidescreen]) return YES;
    return ([[UIScreen mainScreen] bounds].size.height >= 568.0f);
}

// Edge-to-edge phones (iPhone X and later) are far taller than the 4-inch
// screens this layout was built around; the transport controls get more room.
- (BOOL)isTallScreen {
    // iPad always uses the enlarged layout: portrait gets the notched-phone
    // layout scaled up, landscape uses the native side-by-side screen instead.
    if ([self isPadLayout]) return YES;
    // The controller's own view is inset by the tab bar (and would be by the nav
    // bar), so its height is well under the physical screen height. Detect the
    // edge-to-edge phones from the screen instead (iPhone 8 Plus tops out at
    // 736pt; iPhone X and later start at 812pt).
    return [self isWidescreen] && ([[UIScreen mainScreen] bounds].size.height >= 780.0f);
}

- (BOOL)isIPad {
    return ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
}

// iPad gets the native side-by-side layout, except when one-handed mode / the
// non-widescreen debug setting shrinks the app back to the classic 320x480
// size (isWidescreen already returns NO there).
- (BOOL)isPadLayout {
    return [self isIPad] && [self isWidescreen];
}

// Landscape iPad: album art hangs beside the controls column. Portrait iPad
// reuses the scaled-up tall layout instead.
- (BOOL)isSideBySide {
    if (![self isPadLayout]) return NO;
    return (self.view.bounds.size.width > self.view.bounds.size.height);
}

// Dock mode: iPhone rotated to landscape while on Now Playing. iPad keeps its
// native side-by-side layout instead, and the forced legacy-size modes never
// rotate. Note this does NOT depend on isWidescreen: a real 3GS (480pt screen)
// is "non-widescreen" yet should still get the dock.
- (BOOL)isDockMode {
    if ([self isPadLayout]) return NO;
    if ([LTOneHandedMode isActive]) return NO;
    if ([LTDebugSettings forceNonWidescreen]) return NO;
    return (self.view.bounds.size.width > self.view.bounds.size.height);
}

- (void)layoutControls {
    if (self.panning) return;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    BOOL widescreen = [self isWidescreen];

    CGFloat transportH = 40.0f;
    CGFloat bottomInset = LTSafeAreaBottom(self.view);
    CGFloat topInset = LTSafeAreaTop(self.view);

    if ([self isSideBySide]) {
        [self layoutPadSideBySideWithWidth:width height:height topInset:topInset bottomInset:bottomInset];
        self.artworkRestingCenter = self.artworkView.center;
        return;
    }

    if ([self isDockMode]) {
        [self layoutDockWithWidth:width height:height topInset:topInset bottomInset:bottomInset];
        self.artworkRestingCenter = self.artworkView.center;
        return;
    }

    // Portrait path: centered, default-size song info. A dock (or iPad
    // side-by-side) session otherwise leaves it left-aligned and oversized.
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.artistLabel.font = [UIFont systemFontOfSize:13];

    CGFloat bottomPad = (widescreen ? 9.0f : 4.0f) + bottomInset;
    CGFloat transportY = height - bottomPad - transportH;
    CGFloat sliderH = 22.0f;
    CGFloat sliderY = transportY - 8.0f - sliderH;
    CGFloat timeY = sliderY - 4.0f - 16.0f;
    CGFloat titleH = 22.0f;
    CGFloat artistH = 16.0f;

    // Edge-to-edge (notched) phones are far taller than the 4-inch layout this
    // screen was originally designed around. On those, pin the album art to the
    // top, stack the title/artist/scrubber directly beneath it, and let the
    // transport controls span the bottom of the screen.
    BOOL tallScreen = [self isTallScreen];

    if (!widescreen) {
        transportY -= 5.0f;
    }

    if (widescreen) {
        self.bitrateLabel.frame = CGRectMake(16, height - bottomInset - 20, 90, 14);
        CGFloat topPad = 24.0f + topInset;
        self.sourceLabel.hidden = self.showingSwipeHint;
        self.sourceLabel.textAlignment = NSTextAlignmentCenter;
        self.sourceLabel.frame = CGRectMake(12, topPad + 2.0f, width - 24, 24);
        self.pagesHint.frame = self.sourceLabel.frame;

        if (tallScreen) {
            // iPad reuses this notched-phone layout scaled up ~1.35x; phones
            // keep the original metrics.
            BOOL pad = [self isIPad];
            CGFloat s = pad ? 1.35f : 1.0f;
            CGFloat padTitleH = pad ? 30.0f : titleH;
            CGFloat padArtistH = pad ? 20.0f : artistH;

            // Reserve the bottom block for the enlarged controls first, then
            // shrink the artwork if the text/scrubber stack would run into it.
            CGFloat areaH = 184.0f * s;
            CGFloat areaTop = (height - bottomPad) - areaH;

            CGFloat artTop = topPad + 26.0f + 12.0f;
            CGFloat artSize = width - 24.0f;
            CGFloat textBlock = padTitleH + 2.0f + padArtistH + 12.0f * s + 18.0f * s + 16.0f + 14.0f;
            CGFloat artMax = (areaTop - 12.0f) - artTop - textBlock;
            if (artSize > artMax) artSize = artMax;
            if (artSize < 40.0f) artSize = 40.0f;

            self.artworkView.frame = CGRectMake((width - artSize) / 2.0f, artTop, artSize, artSize);
            self.incomingArtworkView.frame = self.artworkView.frame;
            self.spinner.center = self.artworkView.center;

            if (pad) {
                self.titleLabel.font = [UIFont boldSystemFontOfSize:24];
                self.artistLabel.font = [UIFont systemFontOfSize:16];
            }
            CGFloat titleY = artTop + artSize + 14.0f * s;
            self.titleLabel.frame = CGRectMake(12, titleY, width - 24, padTitleH);
            self.artistLabel.frame = CGRectMake(12, titleY + padTitleH + 2.0f, width - 24, padArtistH);

            timeY = titleY + padTitleH + 2.0f + padArtistH + 12.0f * s;
            sliderY = timeY + 18.0f * s;
        } else {
            CGFloat artistY = timeY - 5.0f - artistH;
            CGFloat titleY = artistY - 2.0f - titleH;
            CGFloat artBottom = titleY - 5.0f;
            CGFloat artSize = width - 24.0f;
            CGFloat artTop = artBottom - artSize;
            if (artTop < 0) {
                artTop = 0;
                artSize = artBottom;
            }
            self.artworkView.frame = CGRectMake((width - artSize) / 2.0f, artTop, artSize, artSize);
            self.incomingArtworkView.frame = self.artworkView.frame;
            self.spinner.center = self.artworkView.center;

            self.titleLabel.frame = CGRectMake(12, titleY, width - 24, titleH);
            self.artistLabel.frame = CGRectMake(12, artistY, width - 24, artistH);
        }
    } else {
        self.sourceLabel.hidden = YES;
        self.titleLabel.hidden = self.showingSwipeHint;
        self.artistLabel.hidden = self.showingSwipeHint;
        self.bitrateLabel.frame = CGRectMake(12, 12, 70, 14);
        CGFloat titleY = 10.0f;
        self.titleLabel.frame = CGRectMake(12, titleY, width - 24, titleH);
        self.artistLabel.frame = CGRectMake(12, titleY + titleH + 2.0f, width - 24, 16);
        self.pagesHint.frame = CGRectMake(12, titleY + 12.0f, width - 24, 16);

        CGFloat artworkTop = 54.0f;
        CGFloat artworkBottom = timeY - 5.0f;
        CGFloat artworkSize = MIN(width - 24.0f, artworkBottom - artworkTop);
        if (artworkSize < 1.0f) artworkSize = 0.0f;
        CGFloat artworkY = artworkTop + (artworkBottom - artworkTop - artworkSize) / 2.0f;
        self.artworkView.frame = CGRectMake((width - artworkSize) / 2.0f, artworkY, artworkSize, artworkSize);
        self.incomingArtworkView.frame = self.artworkView.frame;
        self.spinner.center = self.artworkView.center;
    }

    self.elapsedLabel.frame = CGRectMake(16, timeY, 50, 16);
    self.remainingLabel.frame = CGRectMake(width - 66, timeY, 50, 16);
    self.progressSlider.frame = CGRectMake(16, sliderY, width - 32, sliderH);

    if (tallScreen) {
        // Enlarged transport: a big play/pause in the middle, shuffle/repeat up
        // in the top corners and back/next down in the bottom corners. iPad
        // portrait scales all of it up together with the rest of the layout.
        BOOL pad = [self isIPad];
        CGFloat s = pad ? 1.35f : 1.0f;
        CGFloat areaH = 184.0f * s;
        CGFloat areaTop = (height - bottomPad) - areaH;
        CGFloat areaBottom = height - bottomPad;
        CGFloat playSize = 120.0f * s;
        CGFloat midSize = 74.0f * s;
        CGFloat sideSize = midSize;
        CGFloat sideMargin = 24.0f * s;
        CGFloat cornerInset = 46.0f * s;

        self.playButton.frame = CGRectMake((width - playSize) / 2.0f,
                                           areaTop + (areaH - playSize) / 2.0f,
                                           playSize, playSize);
        self.prevButton.frame = CGRectMake(sideMargin, areaBottom - cornerInset - midSize / 2.0f, midSize, midSize);
        self.nextButton.frame = CGRectMake(width - sideMargin - midSize, areaBottom - cornerInset - midSize / 2.0f, midSize, midSize);
        self.shuffleButton.frame = CGRectMake(sideMargin, areaTop + cornerInset - sideSize / 2.0f, sideSize, sideSize);
        self.repeatButton.frame = CGRectMake(width - sideMargin - sideSize, areaTop + cornerInset - sideSize / 2.0f, sideSize, sideSize);

        [self applyCircleToButton:self.playButton diameter:playSize];
        [self applyCircleToButton:self.prevButton diameter:midSize];
        [self applyCircleToButton:self.nextButton diameter:midSize];
        [self applyCircleToButton:self.shuffleButton diameter:sideSize];
        [self applyCircleToButton:self.repeatButton diameter:sideSize];
        [self useTransportCircles];
    } else {
        // Shuffle and loop get the same size as the transport keys, so all five
        // glyphs line up on the one white pill below them.
        CGFloat buttonSize = transportH;
        CGFloat spacing = 12.0f;
        CGFloat totalWidth = buttonSize * 5.0f + spacing * 4.0f;
        if (totalWidth > width - 16.0f) {
            spacing = MAX(6.0f, (width - 16.0f - buttonSize * 5.0f) / 4.0f);
            totalWidth = buttonSize * 5.0f + spacing * 4.0f;
        }
        CGFloat start = (width - totalWidth) / 2.0f;
        CGFloat rowY = transportY + (transportH - buttonSize) / 2.0f;

        self.shuffleButton.frame = CGRectMake(start, rowY, buttonSize, buttonSize);
        self.prevButton.frame = CGRectMake(start + (buttonSize + spacing), rowY, buttonSize, buttonSize);
        self.playButton.frame = CGRectMake(start + (buttonSize + spacing) * 2.0f, rowY, buttonSize, buttonSize);
        self.nextButton.frame = CGRectMake(start + (buttonSize + spacing) * 3.0f, rowY, buttonSize, buttonSize);
        self.repeatButton.frame = CGRectMake(start + (buttonSize + spacing) * 4.0f, rowY, buttonSize, buttonSize);

        // One white pill behind all five keys, rather than a disc behind each.
        // The pill keeps the width it had at the original 18pt spacing, so the
        // tightened row is centred inside a bar that has not changed size.
        CGFloat barSpacing = 18.0f;
        CGFloat barWidth = buttonSize * 5.0f + barSpacing * 4.0f;
        if (barWidth > width - 16.0f) barWidth = width - 16.0f;
        [self useTransportBarInRect:CGRectMake((width - barWidth) / 2.0f, rowY, barWidth, buttonSize)];
    }
    self.artworkRestingCenter = self.artworkView.center;
}

// Landscape iPad: album art hangs on the left (vertically centered) with a
// control column to its right. Source sits at the top; the song/artist/scrubber
// block and the enlarged prev–play–next row form one tight vertically-centered
// bundle, with the shuffle and loop buttons tucked into the bottom-right
// corner. The bounds are already inset by the sidebar rail.
- (void)layoutPadSideBySideWithWidth:(CGFloat)width height:(CGFloat)height topInset:(CGFloat)topInset bottomInset:(CGFloat)bottomInset {
    CGFloat m = 44.0f;
    CGFloat gap = 44.0f;
    CGFloat availH = height - topInset - bottomInset;

    CGFloat artSize = width * 0.42f;
    if (artSize > availH - 100.0f) artSize = availH - 100.0f;
    if (artSize > 620.0f) artSize = 620.0f;
    if (artSize < 140.0f) artSize = 140.0f;
    CGFloat artY = topInset + (availH - artSize) / 2.0f;
    self.artworkView.frame = CGRectMake(m, artY, artSize, artSize);
    self.incomingArtworkView.frame = self.artworkView.frame;
    self.spinner.center = self.artworkView.center;

    CGFloat ctrlX = m + artSize + gap;
    CGFloat ctrlW = width - ctrlX - m;
    CGFloat ctrlRight = ctrlX + ctrlW;
    CGFloat ctrlBottom = height - bottomInset - 8.0f;

    CGFloat topPad = topInset + 20.0f;
    self.sourceLabel.hidden = self.showingSwipeHint;
    self.sourceLabel.textAlignment = NSTextAlignmentLeft;
    self.sourceLabel.frame = CGRectMake(ctrlX, topPad, ctrlW, 26.0f);
    self.pagesHint.frame = self.sourceLabel.frame;
    self.bitrateLabel.frame = CGRectMake(ctrlX, ctrlBottom - 14.0f, 100.0f, 14.0f);

    // Enlarged transport row: a very big play/pause flanked by smaller (but
    // still large) prev/next buttons. Shuffle and loop are small and live in
    // the bottom-right corner.
    CGFloat playSize = 132.0f;
    CGFloat midSize = 78.0f;
    CGFloat smallSize = 56.0f;
    CGFloat rowSpacing = 30.0f;
    CGFloat totalRow = midSize + playSize + midSize + rowSpacing * 2.0f;

    CGFloat titleH = 30.0f;
    CGFloat artistH = 22.0f;
    CGFloat bundleH = titleH + 2.0f + artistH + 14.0f + 22.0f + 28.0f + playSize;

    CGFloat contentTop = topPad + 26.0f + 14.0f;
    CGFloat contentBottom = ctrlBottom - smallSize - 16.0f;
    CGFloat bundleY = contentTop;
    if (contentBottom - contentTop > bundleH) {
        bundleY = contentTop + (contentBottom - contentTop - bundleH) / 2.0f;
    }

    CGFloat titleY = bundleY;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:26];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.frame = CGRectMake(ctrlX, titleY, ctrlW, titleH);
    self.artistLabel.font = [UIFont systemFontOfSize:16];
    self.artistLabel.textAlignment = NSTextAlignmentLeft;
    self.artistLabel.frame = CGRectMake(ctrlX, titleY + titleH + 2.0f, ctrlW, artistH);

    CGFloat sliderY = titleY + titleH + 2.0f + artistH + 14.0f;
    self.elapsedLabel.font = [UIFont systemFontOfSize:12];
    self.remainingLabel.font = [UIFont systemFontOfSize:12];
    self.elapsedLabel.frame = CGRectMake(ctrlX, sliderY - 14.0f, 52.0f, 16.0f);
    self.remainingLabel.frame = CGRectMake(ctrlRight - 52.0f, sliderY - 14.0f, 52.0f, 16.0f);
    self.progressSlider.frame = CGRectMake(ctrlX, sliderY + 2.0f, ctrlW, 22.0f);

    CGFloat rowY = sliderY + 24.0f + 28.0f;
    CGFloat C = ctrlX + ctrlW / 2.0f;
    self.prevButton.frame = CGRectMake(C - totalRow / 2.0f, rowY, midSize, midSize);
    self.playButton.frame = CGRectMake(C - playSize / 2.0f, rowY - (playSize - midSize) / 2.0f, playSize, playSize);
    self.nextButton.frame = CGRectMake(C + totalRow / 2.0f - midSize, rowY, midSize, midSize);

    CGFloat smallY = ctrlBottom - smallSize;
    self.shuffleButton.frame = CGRectMake(ctrlRight - smallSize * 2.0f - 16.0f, smallY, smallSize, smallSize);
    self.repeatButton.frame = CGRectMake(ctrlRight - smallSize, smallY, smallSize, smallSize);

    [self applyCircleToButton:self.playButton diameter:playSize];
    [self applyCircleToButton:self.prevButton diameter:midSize];
    [self applyCircleToButton:self.nextButton diameter:midSize];
    [self applyCircleToButton:self.shuffleButton diameter:smallSize];
    [self applyCircleToButton:self.repeatButton diameter:smallSize];
    [self useTransportCircles];
}

// Dock mode: landscape iPhone on the Now Playing tab. Album art hangs on the
// left (vertically centered); song info, the scrubber and the transport row
// form a column on the right. The queue and lyrics drawers slide in from the
// left and right edges (see layoutPages), so the controls stay available.
- (void)layoutDockWithWidth:(CGFloat)width height:(CGFloat)height topInset:(CGFloat)topInset bottomInset:(CGFloat)bottomInset {
    CGFloat m = 20.0f;
    CGFloat gap = 28.0f;
    CGFloat availH = height - topInset - bottomInset;

    CGFloat artSize = MIN(width * 0.40f, availH - 2.0f * m);
    if (artSize < 120.0f) artSize = 120.0f;
    self.artworkView.frame = CGRectMake(m, topInset + (availH - artSize) / 2.0f, artSize, artSize);
    self.incomingArtworkView.frame = self.artworkView.frame;
    self.spinner.center = self.artworkView.center;

    CGFloat ctrlX = m + artSize + gap;
    CGFloat ctrlW = width - ctrlX - m;
    CGFloat ctrlBottom = height - bottomInset - 8.0f;

    CGFloat transportH = 40.0f;
    CGFloat transportY = ctrlBottom - transportH;
    CGFloat sliderY = transportY - 8.0f - 22.0f;
    CGFloat timeY = sliderY - 4.0f - 16.0f;

    self.elapsedLabel.frame = CGRectMake(ctrlX, timeY, 50, 16);
    self.remainingLabel.frame = CGRectMake(ctrlX + ctrlW - 50, timeY, 50, 16);
    self.progressSlider.frame = CGRectMake(ctrlX, sliderY, ctrlW, 22.0f);

    self.bitrateLabel.hidden = YES;
    // Always show the song info in dock: small-screen layouts hide title/artist
    // while the first-run swipe hint plays, and nothing else restores them here.
    self.titleLabel.hidden = NO;
    self.artistLabel.hidden = NO;
    self.sourceLabel.hidden = self.showingSwipeHint;
    self.sourceLabel.textAlignment = NSTextAlignmentLeft;
    self.sourceLabel.frame = CGRectMake(ctrlX, topInset + 6.0f, ctrlW, 18.0f);
    self.pagesHint.hidden = YES;

    // Title/artist form a block vertically centered within the right column —
    // i.e. centered in the right side of the screen, not over the whole screen
    // — and centered horizontally inside that column.
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.font = [UIFont systemFontOfSize:13];
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    CGFloat titleH2 = 24.0f;
    CGFloat artistH2 = 18.0f;
    CGFloat blockH = titleH2 + 2.0f + artistH2;
    CGFloat infoTop = topInset + 32.0f;
    CGFloat infoBottom = timeY - 16.0f;
    CGFloat blockY = infoTop + (infoBottom - infoTop - blockH) / 2.0f;
    if (blockY < infoTop) blockY = infoTop;
    self.titleLabel.frame = CGRectMake(ctrlX, blockY, ctrlW, titleH2);
    self.artistLabel.frame = CGRectMake(ctrlX, blockY + titleH2 + 2.0f, ctrlW, artistH2);

    // Compact prev–play–next flanked by shuffle/loop, with the spacing adapting
    // to the control column width (tightest on the 480pt landscape 3GS). All
    // five keys are the same size.
    CGFloat buttonSize = transportH;
    CGFloat spacing = (ctrlW - (buttonSize * 5.0f)) / 4.0f;
    if (spacing > 12.0f) spacing = 12.0f;
    if (spacing < 6.0f) spacing = 6.0f;
    CGFloat totalW = buttonSize * 5.0f + spacing * 4.0f;
    CGFloat start = ctrlX + (ctrlW - totalW) / 2.0f;
    CGFloat rowY = transportY + (transportH - buttonSize) / 2.0f;

    self.shuffleButton.frame = CGRectMake(start, rowY, buttonSize, buttonSize);
    self.prevButton.frame = CGRectMake(start + (buttonSize + spacing), rowY, buttonSize, buttonSize);
    self.playButton.frame = CGRectMake(start + (buttonSize + spacing) * 2.0f, rowY, buttonSize, buttonSize);
    self.nextButton.frame = CGRectMake(start + (buttonSize + spacing) * 3.0f, rowY, buttonSize, buttonSize);
    self.repeatButton.frame = CGRectMake(start + (buttonSize + spacing) * 4.0f, rowY, buttonSize, buttonSize);

    // Same single pill as the portrait row. Its width still comes from the
    // original 24pt cap, independent of the tighter glyph spacing above.
    CGFloat barSpacing = (ctrlW - (buttonSize * 5.0f)) / 4.0f;
    if (barSpacing > 24.0f) barSpacing = 24.0f;
    if (barSpacing < 6.0f) barSpacing = 6.0f;
    CGFloat barW = buttonSize * 5.0f + barSpacing * 4.0f;
    [self useTransportBarInRect:CGRectMake(ctrlX + (ctrlW - barW) / 2.0f, rowY, barW, buttonSize)];
}

#pragma mark - Pages layout

- (void)layoutPages {
    if (self.draggingDrawer) return;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    if (w < 1.0f || h < 1.0f) return;
    self.mainPane.frame = CGRectMake(0, 0, w, h);
    if ([self isDockMode]) {
        // Dock drawers are vertical side panels: queue slides from the left
        // edge, lyrics from the right.
        CGFloat dw = [self drawerWidth];
        self.queuePane.frame = CGRectMake(self.queueDrawerOpen ? 0.0f : -dw, 0.0f, dw, h);
        self.statsPane.frame = CGRectMake(self.statsDrawerOpen ? (w - dw) : w, 0.0f, dw, h);
    } else {
        CGFloat drawerH = [self drawerHeight];
        self.queuePane.frame = CGRectMake(0, self.queueDrawerOpen ? 0.0f : -drawerH, w, drawerH);
        self.statsPane.frame = CGRectMake(0, self.statsDrawerOpen ? (h - drawerH) : h, w, drawerH);
    }
}

- (UIView *)makeHandleView {
    UIView *strip = [[UIView alloc] initWithFrame:CGRectZero];
    strip.backgroundColor = [UIColor clearColor];
    strip.userInteractionEnabled = YES;

    UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 5)];
    grip.tag = 99;
    grip.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.55f];
    grip.layer.cornerRadius = 2.5f;
    [strip addSubview:grip];
    return strip;
}

- (void)centerGripInHandle:(UIView *)handle {
    UIView *grip = [handle viewWithTag:99];
    if (!grip) return;
    grip.frame = CGRectMake((handle.bounds.size.width - 40) / 2.0f,
                            (handle.bounds.size.height - 5) / 2.0f, 40, 5);
}

- (void)buildQueuePane {
    self.queueHeader = [[UILabel alloc] initWithFrame:CGRectZero];
    self.queueHeader.font = [UIFont boldSystemFontOfSize:14];
    self.queueHeader.textColor = [UIColor whiteColor];
    self.queueHeader.backgroundColor = [UIColor clearColor];
    [self.queuePane addSubview:self.queueHeader];

    self.queueTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.queueTable.dataSource = self;
    self.queueTable.delegate = self;
    self.queueTable.backgroundColor = [UIColor clearColor];
    self.queueTable.separatorColor = [UIColor colorWithWhite:1.0f alpha:0.25f];
    self.queueTable.rowHeight = 50.0f;
    self.queueTable.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // Always-on reorder handles (Apple Music style): stay in editing mode but
    // with no delete control, so the right-edge grab handles are always active.
    self.queueTable.editing = YES;
    self.queueTable.allowsSelectionDuringEditing = YES;
    [self.queuePane addSubview:self.queueTable];

    self.queueHandle = [self makeHandleView];
    [self.queueHandle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(queueHandleTapped:)]];
    [self.queuePane addSubview:self.queueHandle];

    [self reloadQueue];
}

- (void)reloadQueue {
    if (!self.queueTable) return;
    LTPlayerController *controller = [LTPlayerController sharedController];
    NSInteger count = (NSInteger)controller.queue.count;
    if (count) {
        self.queueHeader.text = [NSString stringWithFormat:@"Up Next  (%d track%@)",
                                 (int)count, count == 1 ? @"" : @"s"];
    } else {
        self.queueHeader.text = @"Queue is empty";
    }
    [self.queueTable reloadData];
    // iOS can drop the table out of editing mode during reloads, which hides
    // the right-edge reorder grips. Re-assert it so the handles always show.
    [self.queueTable setEditing:YES animated:NO];
    LTLog(@"PLAYER_PAGE queue editing=%d reorder=%d shuffle=%d",
          self.queueTable.editing,
          [self tableView:self.queueTable canMoveRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]],
          [[LTPlayerController sharedController] shuffleEnabled]);
}

- (void)buildStatsPane {
    self.lyricsTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    self.lyricsTitle.text = @"Lyrics";
    self.lyricsTitle.font = [UIFont boldSystemFontOfSize:14];
    self.lyricsTitle.textColor = [UIColor colorWithRed:0.35f green:0.68f blue:1.0f alpha:1.0f];
    self.lyricsTitle.textAlignment = NSTextAlignmentCenter;
    self.lyricsTitle.backgroundColor = [UIColor clearColor];
    [self.statsPane addSubview:self.lyricsTitle];

    self.lyricsScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.lyricsScroll.backgroundColor = [UIColor clearColor];
    self.lyricsScroll.alwaysBounceVertical = YES;
    self.lyricsScroll.clipsToBounds = YES;
    self.lyricsScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.statsPane addSubview:self.lyricsScroll];

    self.statsHandle = [self makeHandleView];
    [self.statsHandle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(statsHandleTapped:)]];
    [self.statsPane addSubview:self.statsHandle];
}

- (CGFloat)drawerTopPadding {
    // The queue drawer slides down from the very top of the screen, which on
    // notched phones leaves its first rows under the sensor housing. The status
    // bar is hidden on this screen, so the reported top inset can collapse to 0
    // even though the notch is still there - fall back to its usual height.
    CGFloat inset = LTSafeAreaTop(self.view);
    if (inset < 1.0f && [self isTallScreen]) inset = 47.0f;
    return inset;
}

- (void)layoutPageSubviews {
    CGFloat w = self.view.bounds.size.width;
    if ([self isDockMode]) {
        CGFloat h = self.view.bounds.size.height;
        CGFloat dw = [self drawerWidth];
        CGFloat topPad = [self drawerTopPadding];
        CGFloat strip = 28.0f;

        // Vertical handle strips on the edges facing the main content: queue's
        // on its right edge, lyrics' on its left.
        self.queueHandle.frame = CGRectMake(dw - strip, 0, strip, h);
        self.queueHeader.frame = CGRectMake(16, 10 + topPad, dw - strip - 16, 22);
        self.queueTable.frame = CGRectMake(0, 36 + topPad, dw - strip, h - 36 - topPad);

        self.statsHandle.frame = CGRectMake(0, 0, strip, h);
        self.lyricsTitle.frame = CGRectMake(16, 10 + topPad, dw - strip - 16, 22);
        self.lyricsScroll.frame = CGRectMake(16, 36 + topPad, dw - strip - 32, h - 36 - topPad);

        [self layoutDockHandleGrip:self.queueHandle];
        [self layoutDockHandleGrip:self.statsHandle];
        return;
    }

    CGFloat drawerH = [self drawerHeight];
    CGFloat handleH = 40.0f;
    CGFloat topPad = [self drawerTopPadding];

    self.queueHandle.frame = CGRectMake(0, drawerH - handleH, w, handleH);
    self.queueHeader.frame = CGRectMake(16, 10 + topPad, w - 32, 22);
    self.queueTable.frame = CGRectMake(0, 36 + topPad, w, drawerH - 36 - topPad - handleH);

    self.statsHandle.frame = CGRectMake(0, 0, w, handleH);
    self.lyricsTitle.frame = CGRectMake(16, handleH + 2, w - 32, 22);
    self.lyricsScroll.frame = CGRectMake(16, handleH + 26, w - 32, drawerH - handleH - 34);

    [self centerGripInHandle:self.queueHandle];
    [self centerGripInHandle:self.statsHandle];
}

// Vertical handle strip on a dock side-drawer: the grip becomes a vertical bar
// centered in the strip.
- (void)layoutDockHandleGrip:(UIView *)handle {
    UIView *grip = [handle viewWithTag:99];
    if (!grip) return;
    grip.frame = CGRectMake((handle.bounds.size.width - 5.0f) / 2.0f,
                            (handle.bounds.size.height - 40.0f) / 2.0f, 5.0f, 40.0f);
}

- (void)revealQueue {
    [self setQueueDrawerOpen:YES animated:YES];
}

- (void)revealNowPlaying {
    [self setQueueDrawerOpen:NO animated:YES];
    [self setStatsDrawerOpen:NO animated:YES];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    self.navigationController.navigationBarHidden = YES;
    self.navigationItem.rightBarButtonItem = nil;
    [self refreshSourceLabel];
    [self applyArtworkBackgroundPref];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(trackDidChange:)
                                                 name:LTPlayerTrackDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(stateDidChange:)
                                                 name:LTPlayerStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(queueDidChange:)
                                                 name:LTPlayerQueueDidChangeNotification
                                               object:nil];
    [self refreshTrack];
    [self startTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopTimer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

// The Now Playing tab is the only landscape-capable screen (the tab bar gates
// the rest to portrait): it drives the dock layout when the device is rotated.
- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - Refresh

- (void)refreshTrack {
    [self resetArtworkPresentation];
    [self refreshLyricsForCurrentTrack];
    LTTrack *track = [[LTPlayerController sharedController] currentTrack];
    if (!track) {
        self.titleLabel.text = @"Nothing playing";
        self.artistLabel.text = @"";
        self.artworkView.image = nil;
        if (self.backgroundImageView) self.backgroundImageView.image = nil;
        return;
    }
    self.titleLabel.text = track.title;
    NSMutableString *artist = [NSMutableString string];
    if (track.artist.length) [artist appendString:track.artist];
    if (track.album.length) {
        if (artist.length) [artist appendString:@"  •  "];
        [artist appendString:track.album];
    }
    self.artistLabel.text = artist;
    [self refreshSourceLabel];

    self.artworkView.image = nil;
    LTLog(@"PLAYER refresh track=%@ url=%@", track.title, track.thumbnailURL.length ? track.thumbnailURL : @"(none)");
    if (track.thumbnailURL.length) {
        NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:track.thumbnailURL];
        [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
            if (image && [track.videoId isEqualToString:[[LTPlayerController sharedController] currentTrack].videoId]) {
                [self setArtworkImage:image forVideoId:track.videoId];
            }
        }];
    } else {
        __weak LTPlayerViewController *weakSelf = self;
        [[LTPlaylistStore sharedStore] resolveThumbnailForTrack:track completion:^(NSString *thumbnailURL) {
            LTPlayerViewController *strongSelf = weakSelf;
            if (!strongSelf || !thumbnailURL.length) return;
            strongSelf.titleLabel.text = track.title;
            NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:thumbnailURL];
            [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
                if (image && [track.videoId isEqualToString:[[LTPlayerController sharedController] currentTrack].videoId]) {
                    [strongSelf setArtworkImage:image forVideoId:track.videoId];
                }
            }];
        }];
    }
    [self refreshControls];
    [self reloadQueue];
    [self refreshLyricsForCurrentTrack];
    [self maybeShowSwipeHint];
}

- (void)refreshSourceLabel {
    self.sourceLabel.text = [[LTPlayerController sharedController] queueSourceName] ?: @"";
}

#pragma mark - Swipe hint

// On the first song played in a session, briefly show the drawer gesture hint
// in place of the source label (or the title/artist block on small phones),
// then cross-fade back to the real text.
- (void)maybeShowSwipeHint {
    if (sHasShownSwipeHint) return;
    sHasShownSwipeHint = YES;
    [self showSwipeHint];
}

- (void)showSwipeHint {
    self.showingSwipeHint = YES;
    [self layoutControls];
    self.pagesHint.hidden = NO;
    self.pagesHint.alpha = 0.0f;
    [UIView animateWithDuration:0.35 animations:^{
        self.pagesHint.alpha = 1.0f;
    }];
    [self.swipeHintTimer invalidate];
    self.swipeHintTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                           target:self
                                                         selector:@selector(hideSwipeHint)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)hideSwipeHint {
    self.swipeHintTimer = nil;
    self.showingSwipeHint = NO;
    [self layoutControls];

    UIView *primary = [self isWidescreen] ? self.sourceLabel : self.titleLabel;
    UIView *secondary = [self isWidescreen] ? nil : self.artistLabel;
    primary.alpha = 0.0f;
    secondary.alpha = 0.0f;
    [UIView animateWithDuration:0.35 animations:^{
        self.pagesHint.alpha = 0.0f;
        primary.alpha = 1.0f;
        secondary.alpha = 1.0f;
    } completion:^(BOOL finished) {
        self.pagesHint.hidden = YES;
        self.pagesHint.alpha = 1.0f;
    }];
}

- (BOOL)artworkBackgroundEnabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"LTPlayerArtworkBackground"] == nil) {
        BOOL modern = ([UIDevice currentDevice].systemVersion.intValue >= 7);
        [defaults setBool:modern forKey:@"LTPlayerArtworkBackground"];
        return modern;
    }
    return [defaults boolForKey:@"LTPlayerArtworkBackground"];
}

// Create or remove the album-art background/scrim based on the current toggle.
// Called at load and again each time the view appears so changes apply live.
- (void)applyArtworkBackgroundPref {
    if (![self artworkBackgroundEnabled]) {
        [self.backgroundImageView removeFromSuperview];
        self.backgroundImageView = nil;
        [self.scrimView removeFromSuperview];
        self.scrimView = nil;
        return;
    }
    if (!self.backgroundImageView) {
        self.backgroundImageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
        self.backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
        self.backgroundImageView.clipsToBounds = YES;
        self.backgroundImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view insertSubview:self.backgroundImageView atIndex:0];

        self.scrimView = [[UIView alloc] initWithFrame:self.view.bounds];
        self.scrimView.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.30f];
        self.scrimView.userInteractionEnabled = NO;
        self.scrimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view insertSubview:self.scrimView aboveSubview:self.backgroundImageView];
    }
    // A freshly created image view starts empty, so put back the blurred art we
    // already cached for this track rather than waiting for it to load again.
    [self restoreCachedBackdrop];
}

// Re-applies the cached blur for the current track, so re-entering the view does
// not show an empty backdrop while the artwork reloads.
- (void)restoreCachedBackdrop {
    NSString *videoId = [[LTPlayerController sharedController] currentTrack].videoId;
    if (!videoId.length) return;
    UIImage *blurred = [self.blurCache objectForKey:videoId];
    if (!blurred) return;
    [self applyBackdropImage:blurred palette:[self.paletteCache objectForKey:videoId]];
}

// Shows a blurred backdrop and tints the ambient pulse to match it.
- (void)applyBackdropImage:(UIImage *)blurred palette:(NSArray *)palette {
    if (!blurred) return;
    self.backgroundImageView.image = blurred;
}

- (void)setArtworkImage:(UIImage *)image forVideoId:(NSString *)videoId {
    if (!image) return;
    self.artworkView.image = image;
    if (![self artworkBackgroundEnabled]) return;
    UIImage *blurred = [self.blurCache objectForKey:videoId];
    if (blurred) {
        [self applyBackdropImage:blurred
                         palette:[self.paletteCache objectForKey:videoId]];
        return;
    }
    __weak LTPlayerViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        UIImage *result = [LTGraphics blurredImageFromImage:image];
        // The thumbnail is tiny, so sampling it for the glow tints is cheap.
        NSArray *palette = [LTGraphics dominantColorsFromImage:result count:3];
        if (!result) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            LTPlayerViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            NSString *currentId = [[LTPlayerController sharedController] currentTrack].videoId;
            if (videoId.length && [videoId isEqualToString:currentId]) {
                [strongSelf.blurCache setObject:result forKey:videoId];
                [strongSelf.paletteCache setObject:palette forKey:videoId];
                [strongSelf applyBackdropImage:result palette:palette];
                LTLog(@"PLAYER_BG bounds=%.0f x %.0f frame=%.0f,%.0f imgSz=%.0f x %.0f tints=%lu",
                      strongSelf.view.bounds.size.width, strongSelf.view.bounds.size.height,
                      strongSelf.backgroundImageView.frame.size.width, strongSelf.backgroundImageView.frame.size.height,
                      result.size.width, result.size.height, (unsigned long)palette.count);
            }
        });
    });
}

- (void)refreshControls {
    LTPlayerController *controller = [LTPlayerController sharedController];
    NSInteger kbps = [controller audioBitrateKbps];
    BOOL showKbps = [[NSUserDefaults standardUserDefaults] boolForKey:@"LTShowKbpsCounter"];
    self.bitrateLabel.text = (showKbps && kbps > 0) ? [NSString stringWithFormat:@"%d kbps", (int)kbps] : @"";
    if ([controller isLoading]) {
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
    }

    [self applyTransportImages];
}

// On the tall edge-to-edge layout the transport controls are drawn much larger,
// so they are rendered from the Font Awesome glyphs at the size they need rather
// than the fixed 30x30 bitmap assets. Older layouts keep the original bitmaps.
- (void)applyTransportImages {
    LTPlayerController *controller = [LTPlayerController sharedController];

    if ([self isTallScreen] || [self isSideBySide]) {
        BOOL pad = [self isIPad];
        BOOL sb = [self isSideBySide];
        // Circles are big on the tall layout and very big in iPad side-by-side,
        // so the glyphs inside stay relatively small for a cleaner ring.
        CGFloat prevNextGlyph = pad ? (sb ? 26.0f : 52.0f) : 34.0f;
        CGFloat smallGlyph = pad ? (sb ? 22.0f : 52.0f) : 34.0f;
        CGFloat playGlyph = pad ? (sb ? 40.0f : 84.0f) : 56.0f;
        UIColor *normal = [UIColor blackColor];
        UIColor *highlighted = [UIColor colorWithRed:0.349f green:0.678f blue:1.0f alpha:1.0f];

        [self.prevButton setImage:[LTGraphics glyphIcon:0xF04A size:prevNextGlyph color:normal] forState:UIControlStateNormal];
        [self.nextButton setImage:[LTGraphics glyphIcon:0xF04E size:prevNextGlyph color:normal] forState:UIControlStateNormal];

        unichar playGlyphCode = [controller isPlaying] ? 0xF04C : 0xF04B;
        [self.playButton setImage:[LTGraphics glyphIcon:playGlyphCode size:playGlyph color:normal] forState:UIControlStateNormal];

        [self.shuffleButton setImage:[LTGraphics glyphIcon:0xF074 size:smallGlyph color:normal] forState:UIControlStateNormal];
        [self.shuffleButton setImage:[LTGraphics glyphIcon:0xF074 size:smallGlyph color:highlighted] forState:UIControlStateSelected];

        UIImage *repeatNormal = [LTGraphics repeatIconOfSize:smallGlyph color:normal];
        UIImage *repeatSelected = [LTGraphics repeatIconOfSize:smallGlyph color:highlighted];
        UIImage *repeatOneNormal = [LTGraphics repeatOneIconOfSize:smallGlyph color:normal];
        UIImage *repeatOneSelected = [LTGraphics repeatOneIconOfSize:smallGlyph color:highlighted];
        if (!repeatNormal) {
            repeatNormal = [UIImage imageNamed:@"IcoRepeat"];
            repeatSelected = [UIImage imageNamed:@"IcoRepeatBlue"];
        }
        if (!repeatOneNormal) {
            repeatOneNormal = [UIImage imageNamed:@"IcoRepeatOne"];
            repeatOneSelected = [UIImage imageNamed:@"IcoRepeatOneBlue"];
        }
        BOOL repeatOne = (controller.repeatMode == LTRepeatModeOne);
        [self.repeatButton setImage:(repeatOne ? repeatOneNormal : repeatNormal) forState:UIControlStateNormal];
        [self.repeatButton setImage:(repeatOne ? repeatOneSelected : repeatSelected) forState:UIControlStateSelected];
        self.repeatButton.selected = (controller.repeatMode != LTRepeatModeOff);
        self.shuffleButton.selected = controller.shuffleEnabled;
        return;
    }

    // Standard layout: the same Lucide glyphs, sized for the compact row. All
    // five discs are the same diameter, so the glyphs are too.
    CGFloat transportGlyph = 27.0f;
    CGFloat smallGlyph = 27.0f;
    UIColor *black = [UIColor blackColor];
    UIColor *blue = [UIColor colorWithRed:0.349f green:0.678f blue:1.0f alpha:1.0f];

    if ([controller isPlaying]) {
        [self.playButton setImage:[LTGraphics glyphIcon:0xF04C size:transportGlyph color:black] forState:UIControlStateNormal];
    } else {
        [self.playButton setImage:[LTGraphics glyphIcon:0xF04B size:transportGlyph color:black] forState:UIControlStateNormal];
    }
    [self.prevButton setImage:[LTGraphics glyphIcon:0xF04A size:transportGlyph color:black] forState:UIControlStateNormal];
    [self.nextButton setImage:[LTGraphics glyphIcon:0xF04E size:transportGlyph color:black] forState:UIControlStateNormal];
    [self.shuffleButton setImage:[LTGraphics glyphIcon:0xF074 size:smallGlyph color:black] forState:UIControlStateNormal];
    [self.shuffleButton setImage:[LTGraphics glyphIcon:0xF074 size:smallGlyph color:blue] forState:UIControlStateSelected];
    self.shuffleButton.selected = controller.shuffleEnabled;

    BOOL repeatOne = (controller.repeatMode == LTRepeatModeOne);
    UIImage *repeatOff = [LTGraphics repeatIconOfSize:smallGlyph color:black];
    UIImage *repeatOn = [LTGraphics repeatIconOfSize:smallGlyph color:blue];
    UIImage *repeatOneOff = [LTGraphics repeatOneIconOfSize:smallGlyph color:black];
    UIImage *repeatOneOn = [LTGraphics repeatOneIconOfSize:smallGlyph color:blue];
    if (!repeatOff || !repeatOneOff) return; // keep the asset images if Lucide fails
    [self.repeatButton setImage:(repeatOne ? repeatOneOff : repeatOff) forState:UIControlStateNormal];
    [self.repeatButton setImage:(repeatOne ? repeatOneOn : repeatOn) forState:UIControlStateSelected];
    self.repeatButton.selected = (controller.repeatMode != LTRepeatModeOff);
}

- (void)updateProgress {
    LTPlayerController *controller = [LTPlayerController sharedController];
    NSTimeInterval duration = [controller duration];
    NSTimeInterval time = [controller currentTime];
    if (duration > 0 && !self.scrubbing) {
        self.progressSlider.maximumValue = duration;
        self.progressSlider.value = time;
        self.elapsedLabel.text = [self formatTime:time];
        self.remainingLabel.text = [NSString stringWithFormat:@"-%@", [self formatTime:duration - time]];
    } else if (duration <= 0) {
        self.elapsedLabel.text = [self formatTime:time];
    }
    if (self.statsDrawerOpen) {
        [self updateLyricHighlightForTime:time];
    }
}

// Fast tick used only while the lyrics drawer is open so the synced line keeps
// in step with the music instead of snapping every half second.
- (void)lyricsTick {
    if (!self.statsDrawerOpen) return;
    [self updateLyricHighlightForTime:[[LTPlayerController sharedController] currentTime]];
}

- (NSString *)formatTime:(NSTimeInterval)time {
    if (time < 0 || isnan(time)) time = 0;
    NSInteger seconds = (NSInteger)time;
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

#pragma mark - Timer

// The synced line is re-picked on this faster tick while the lyrics drawer is
// open. updateProgress only runs every 0.5s, which left the highlight up to half
// a second behind the audio. stopTimer invalidates this along with the rest.
- (void)syncLyricsTimer {
    if (self.statsDrawerOpen) {
        if (!self.lyricsTimer) {
            self.lyricsTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                                target:self
                                                              selector:@selector(lyricsTick)
                                                              userInfo:nil
                                                               repeats:YES];
        }
    } else {
        [self.lyricsTimer invalidate];
        self.lyricsTimer = nil;
    }
}

- (void)startTimer {
    [self stopTimer];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
    [self.lyricsTimer invalidate];
    self.lyricsTimer = nil;
}

#pragma mark - Actions

- (void)playTapped:(id)sender {
    [[LTPlayerController sharedController] togglePlayPause];
}

- (void)nextTapped:(id)sender {
    [[LTPlayerController sharedController] nextTrack];
}

- (void)prevTapped:(id)sender {
    [[LTPlayerController sharedController] previousTrack];
}

- (void)shuffleTapped:(id)sender {
    [[LTPlayerController sharedController] toggleShuffle];
    [self refreshControls];
}

- (void)repeatTapped:(id)sender {
    [[LTPlayerController sharedController] cycleRepeatMode];
    [self refreshControls];
}

- (void)sliderChanged:(id)sender {
    self.scrubbing = YES;
    self.elapsedLabel.text = [self formatTime:self.progressSlider.value];
}

- (void)sliderTouchedUp:(id)sender {
    [[LTPlayerController sharedController] seekToTime:self.progressSlider.value];
    self.scrubbing = NO;
}

#pragma mark - Notifications

- (void)trackDidChange:(NSNotification *)notification {
    [self refreshTrack];
}

- (void)stateDidChange:(NSNotification *)notification {
    [self refreshControls];
    [self refreshLyricsForCurrentTrack];
}

- (void)queueDidChange:(NSNotification *)notification {
    [self refreshControls];
    [self reloadQueue];
    [self refreshLyricsForCurrentTrack];
}

#pragma mark - Lyrics

- (void)refreshLyricsForCurrentTrack {
    if (!self.lyricsScroll) return;
    LTTrack *track = [[LTPlayerController sharedController] currentTrack];
    if (!track || !track.videoId.length) {
        self.lyricsVideoId = nil;
        self.lyricLines = nil;
        [self showLyricsMessage:@"Nothing playing.\n\nSwipe up for lyrics\nonce a song starts."];
        return;
    }
    if ([self.lyricsVideoId isEqualToString:track.videoId]) {
        return;
    }
    self.lyricsVideoId = track.videoId;
    self.lyricLines = nil;
    [self showLyricsMessage:@"Loading lyrics\u2026"];
    __weak LTPlayerViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] fetchTimedLyricsForVideoId:track.videoId completion:^(NSDictionary *result, NSError *error) {
        LTPlayerViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (![[[LTPlayerController sharedController] currentTrack].videoId isEqualToString:track.videoId]) {
            return;
        }
        if (error || !result) {
            strongSelf.lyricsVideoId = nil;
            [strongSelf showLyricsMessage:@"No lyrics available\nfor this song."];
            return;
        }
        BOOL timed = [[result objectForKey:@"hasTimestamps"] boolValue];
        NSArray *lines = [result objectForKey:@"lines"];
        if (timed && [lines isKindOfClass:[NSArray class]] && lines.count) {
            strongSelf.lyricLines = lines;
            strongSelf.lyricsVideoId = track.videoId;
            [strongSelf renderLyricLinesAnimated:NO];
            [strongSelf updateLyricHighlightForTime:[[LTPlayerController sharedController] currentTime]];
        } else {
            NSString *plain = [result objectForKey:@"lyrics"];
            if (plain.length) {
                strongSelf.lyricsVideoId = track.videoId;
                [strongSelf showPlainLyrics:plain];
            } else {
                strongSelf.lyricsVideoId = nil;
                [strongSelf showLyricsMessage:@"No lyrics available\nfor this song."];
            }
        }
    }];
}

- (void)showLyricsMessage:(NSString *)message {
    self.activeLyricIndex = -1;
    self.lyricLabelViews = nil;
    for (UIView *sub in self.lyricsScroll.subviews) {
        if (sub.tag == 77) [sub removeFromSuperview];
    }
    UILabel *label = [[UILabel alloc] initWithFrame:self.lyricsScroll.bounds];
    label.tag = 77;
    label.text = message;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
    label.backgroundColor = [UIColor clearColor];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.lyricsScroll addSubview:label];
    if (self.lyricsScroll.subviews.count > 1) {
        for (UIView *sub in self.lyricsScroll.subviews) {
            if (sub != label) [sub removeFromSuperview];
        }
    }
    self.lyricsScroll.contentSize = self.lyricsScroll.bounds.size;
}

- (void)showPlainLyrics:(NSString *)plain {
    self.activeLyricIndex = -1;
    self.lyricLabelViews = nil;
    for (UIView *sub in self.lyricsScroll.subviews) {
        if (sub.tag == 77) [sub removeFromSuperview];
    }
    if (!plain.length) {
        [self showLyricsMessage:@"No lyrics available\nfor this song."];
        return;
    }
    NSArray *rawLines = [plain componentsSeparatedByString:@"\n"];
    NSMutableArray *labels = [NSMutableArray array];
    CGFloat y = 14.0f;
    CGFloat inset = 14.0f;
    CGFloat w = self.lyricsScroll.bounds.size.width - inset * 2.0f;
    UIFont *font = [UIFont systemFontOfSize:15];
    CGFloat lineHeight = [@" " sizeWithFont:font].height;
    for (NSString *text in rawLines) {
        CGFloat h = [self lyricRowHeightForText:text font:font width:w];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(inset, y, w, h)];
        label.tag = 77;
        label.text = text.length ? text : @" ";
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = font;
        label.textColor = [UIColor colorWithWhite:0.82f alpha:1.0f];
        label.backgroundColor = [UIColor clearColor];
        [self.lyricsScroll addSubview:label];
        [labels addObject:label];
        y += h + lineHeight;
    }
    self.lyricLabelViews = labels;
    self.lyricsScroll.contentSize = CGSizeMake(w + inset * 2.0f, y + 14.0f);
}

- (CGFloat)lyricRowHeightForText:(NSString *)text font:(UIFont *)font width:(CGFloat)w {
    CGFloat minH = [@" " sizeWithFont:font].height;
    if (!text.length) return minH;
    CGSize sz = [text sizeWithFont:font constrainedToSize:CGSizeMake(w, CGFLOAT_MAX) lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(minH, ceilf(sz.height));
}

- (void)renderLyricLinesAnimated:(BOOL)animated {
    self.activeLyricIndex = -1;
    for (UIView *sub in self.lyricsScroll.subviews) {
        if (sub.tag == 77) [sub removeFromSuperview];
    }
    if (!self.lyricLines.count) {
        [self showLyricsMessage:@"No lyrics available\nfor this song."];
        return;
    }
    NSMutableArray *labels = [NSMutableArray array];
    CGFloat y = 16.0f;
    CGFloat inset = 14.0f;
    CGFloat w = self.lyricsScroll.bounds.size.width - inset * 2.0f;
    UIFont *font = [UIFont systemFontOfSize:16];
    CGFloat lineHeight = [@" " sizeWithFont:font].height;
    CGFloat gap = lineHeight * 2.0f;
    for (NSDictionary *line in self.lyricLines) {
        NSString *text = [line objectForKey:@"text"];
        CGFloat h = [self lyricRowHeightForText:text font:font width:w];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(inset, y, w, h)];
        label.tag = 77;
        label.text = text.length ? text : @" ";
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = font;
        label.textColor = [UIColor colorWithWhite:0.18f alpha:1.0f];
        label.backgroundColor = [UIColor clearColor];
        [self.lyricsScroll addSubview:label];
        [labels addObject:label];
        y += h + gap;
    }
    self.lyricLabelViews = labels;
    self.lyricsScroll.contentSize = CGSizeMake(w + inset * 2.0f, y + 16.0f);
}

- (void)updateLyricHighlightForTime:(NSTimeInterval)time {
    if (!self.lyricLines.count || !self.lyricLabelViews.count) return;
    NSTimeInterval ms = time * 1000.0;
    NSInteger index = -1;
    for (NSInteger i = 0; i < (NSInteger)self.lyricLines.count; i++) {
        NSDictionary *line = [self.lyricLines objectAtIndex:(NSUInteger)i];
        NSTimeInterval start = [[line objectForKey:@"start"] doubleValue];
        NSTimeInterval end = [[line objectForKey:@"end"] doubleValue];
        if (ms >= start && ms < end) { index = i; break; }
    }
    if (index == self.activeLyricIndex) return;
    self.activeLyricIndex = index;
    UIColor *activeColor = [UIColor whiteColor];
    UIColor *idleColor = [UIColor colorWithWhite:0.18f alpha:1.0f];
    for (NSInteger i = 0; i < (NSInteger)self.lyricLabelViews.count; i++) {
        UILabel *label = [self.lyricLabelViews objectAtIndex:(NSUInteger)i];
        UIColor *target = (i == index) ? activeColor : idleColor;
        // Compare via isEqual: tapping the fast tick must not restart fades for
        // labels that already hold the target color (UIColor instances differ).
        if (![label.textColor isEqual:target]) {
            label.textColor = target;
        }
    }
    if (index >= 0) {
        UILabel *active = [self.lyricLabelViews objectAtIndex:(NSUInteger)index];
        CGFloat targetY = active.frame.origin.y - self.lyricsScroll.bounds.size.height / 2.0f + active.frame.size.height / 2.0f;
        CGFloat maxY = MAX(0.0f, self.lyricsScroll.contentSize.height - self.lyricsScroll.bounds.size.height);
        targetY = MAX(0.0f, MIN(targetY, maxY));
        [self.lyricsScroll setContentOffset:CGPointMake(0, targetY) animated:YES];
    }
}

#pragma mark - Queue table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[[LTPlayerController sharedController] queue].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellId = @"LTPageQueueCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellId];
    if (!cell) {
        cell = [[LTSimpleCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
        cell.showsReorderControl = YES;
    }
    LTPlayerController *controller = [LTPlayerController sharedController];
    LTTrack *track = [[controller queue] objectAtIndex:(NSUInteger)indexPath.row];
    NSInteger idx = (NSInteger)indexPath.row;
    cell.imageView.image = nil;
    if (idx == controller.currentIndex) {
        cell.imageView.image = [self scaledQueueIcon:[LTGraphics glyphIcon:0xF04B
                                                                      size:20.0f
                                                                     color:[UIColor colorWithRed:0.35f green:0.68f blue:1.0f alpha:1.0f]]];
        cell.imageView.contentMode = UIViewContentModeCenter;
        cell.textLabel.text = track.title;
        cell.textLabel.textColor = [UIColor colorWithRed:0.35f green:0.68f blue:1.0f alpha:1.0f];
    } else {
        cell.textLabel.text = [NSString stringWithFormat:@"%d. %@", (int)idx + 1, track.title];
        cell.textLabel.textColor = [UIColor whiteColor];
    }
    NSMutableString *detail = [NSMutableString string];
    if (track.artist.length) [detail appendString:track.artist];
    if (track.album.length) {
        if (detail.length) [detail appendString:@"  \u2022  "];
        [detail appendString:track.album];
    }
    cell.detailTextLabel.text = detail;
    return cell;
}

- (UIImage *)scaledQueueIcon:(UIImage *)image {
    if (!image) return nil;
    CGFloat s = [UIScreen mainScreen].scale;
    CGSize size = CGSizeMake(14.0f, 14.0f);
    UIGraphicsBeginImageContextWithOptions(size, NO, s);
    [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    LTLog(@"PLAYER_PAGE jump to %d", (int)indexPath.row);
    [[LTPlayerController sharedController] jumpToIndex:indexPath.row];
    [self revealNowPlaying];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
    LTLog(@"PLAYER_PAGE move %d -> %d", (int)fromIndexPath.row, (int)toIndexPath.row);
    [[LTPlayerController sharedController] moveTrackAtIndex:fromIndexPath.row toIndex:toIndexPath.row];
    [self reloadQueue];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        LTLog(@"PLAYER_PAGE delete row %d", (int)indexPath.row);
        [[LTPlayerController sharedController] removeTrackAtIndex:indexPath.row];
        [self reloadQueue];
    }
}

@end
