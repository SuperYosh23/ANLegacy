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
@property (nonatomic, strong) UILabel *statsTitle;
@property (nonatomic, strong) UITextView *statsText;
@property (nonatomic, strong) UILabel *pagesHint;
@property (nonatomic, assign) BOOL queueDrawerOpen;
@property (nonatomic, assign) BOOL statsDrawerOpen;
@property (nonatomic, assign) BOOL draggingDrawer;
@property (nonatomic, assign) NSInteger activeDragIndex;
@property (nonatomic, assign) BOOL dragIndexResolved;
@property (nonatomic, assign) CGFloat drawerDragStartY;
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) UIView *scrimView;
@property (nonatomic, strong) NSCache *blurCache;
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
@property (nonatomic, strong) NSTimer *swipeHintTimer;
@property (nonatomic, assign) BOOL showingSwipeHint;
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) BOOL panning;
@property (nonatomic, assign) CGPoint artworkRestingCenter;
@property (nonatomic, assign) CGFloat panBaseX;
@property (nonatomic, assign) BOOL panCommitted;
@property (nonatomic, assign) NSInteger panSwipeDir;
@property (nonatomic, assign) NSInteger lastGlyphMode;
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

    self.pagesHint = [[UILabel alloc] init];
    self.pagesHint.text = @"Swipe down for queue   \u00B7   Swipe up for stats";
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
    if (gestureRecognizer == self.swipePan) {
        CGPoint v = [self.swipePan velocityInView:self.mainPane];
        return fabs(v.x) > fabs(v.y);
    }
    if (gestureRecognizer == self.mainVerticalPan) {
        CGPoint v = [self.mainVerticalPan velocityInView:self.mainPane];
        return fabs(v.y) > fabs(v.x);
    }
    if (gestureRecognizer == self.queueDrag || gestureRecognizer == self.statsDrag) {
        CGPoint v = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
        return fabs(v.y) >= fabs(v.x);
    }
    return YES;
}

// Drawer drags must only start outside the scrollable middle region, so the
// queue table / stats text keep their normal scrolling. Touches on the handle
// strips and empty drawer margins move the drawer instead.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.queueDrag && self.queueTable) {
        CGPoint p = [touch locationInView:self.queueTable];
        return !CGRectContainsPoint(self.queueTable.bounds, p);
    }
    if (gestureRecognizer == self.statsDrag && self.statsText) {
        CGPoint p = [touch locationInView:self.statsText];
        return !CGRectContainsPoint(self.statsText.bounds, p);
    }
    return YES;
}

- (CGFloat)drawerHeight {
    CGFloat h = self.view.bounds.size.height;
    CGFloat drawerH = floorf(h * 0.70f);
    if (drawerH < 120.0f) drawerH = h;
    return drawerH;
}

- (void)queueHandleTapped:(UITapGestureRecognizer *)tap {
    [self setQueueDrawerOpen:NO animated:YES];
}

- (void)statsHandleTapped:(UITapGestureRecognizer *)tap {
    [self setStatsDrawerOpen:NO animated:YES];
}

- (void)setQueueDrawerOpen:(BOOL)open animated:(BOOL)animated {
    if (open && self.statsDrawerOpen) {
        [self setStatsDrawerOpen:NO animated:animated];
    }
    self.queueDrawerOpen = open;
    CGFloat drawerH = [self drawerHeight];
    CGRect target = self.queuePane.frame;
    target.size.height = drawerH;
    target.origin.y = open ? 0.0f : -drawerH;
    void (^updates)(void) = ^{ self.queuePane.frame = target; };
    if (animated) {
        [UIView animateWithDuration:0.28 animations:updates];
    } else {
        updates();
    }
}

- (void)setStatsDrawerOpen:(BOOL)open animated:(BOOL)animated {
    if (open && self.queueDrawerOpen) {
        [self setQueueDrawerOpen:NO animated:animated];
    }
    self.statsDrawerOpen = open;
    CGFloat h = self.view.bounds.size.height;
    CGFloat drawerH = [self drawerHeight];
    CGRect target = self.statsPane.frame;
    target.size.height = drawerH;
    target.origin.y = open ? (h - drawerH) : h;
    void (^updates)(void) = ^{ self.statsPane.frame = target; };
    if (animated) {
        [UIView animateWithDuration:0.28 animations:updates];
    } else {
        updates();
    }
}

#pragma mark - Interactive drawer dragging

// A drag can come from a drawer's own handle pan or from a vertical pan on the
// main view; both drive the same interactive slide.
- (void)beginDrawerDragAtIndex:(NSInteger)index {
    self.activeDragIndex = index;
    self.draggingDrawer = YES;
    UIView *drawer = (index == 0) ? self.queuePane : self.statsPane;
    self.drawerDragStartY = drawer.frame.origin.y;
}

- (void)updateDrawerDragWithTranslation:(CGFloat)ty {
    BOOL isQueue = (self.activeDragIndex == 0);
    UIView *drawer = isQueue ? self.queuePane : self.statsPane;
    CGFloat h = self.view.bounds.size.height;
    CGFloat drawerH = [self drawerHeight];
    CGFloat minY = isQueue ? -drawerH : (h - drawerH);
    CGFloat maxY = isQueue ? 0.0f : h;
    CGFloat y = self.drawerDragStartY + ty;
    if (y < minY) y = minY + (y - minY) * 0.35f;
    if (y > maxY) y = maxY + (y - maxY) * 0.35f;
    drawer.frame = CGRectMake(0, y, drawer.frame.size.width, drawerH);
}

- (void)endDrawerDragWithVelocity:(CGFloat)vy {
    BOOL isQueue = (self.activeDragIndex == 0);
    UIView *drawer = isQueue ? self.queuePane : self.statsPane;
    CGFloat h = self.view.bounds.size.height;
    CGFloat drawerH = [self drawerHeight];
    CGFloat openY = isQueue ? 0.0f : (h - drawerH);
    CGFloat closedY = isQueue ? -drawerH : h;
    self.draggingDrawer = NO;
    CGFloat projected = drawer.frame.origin.y + vy * 0.15f;
    BOOL open;
    if (isQueue) {
        open = projected > closedY + (openY - closedY) * 0.5f;
    } else {
        open = projected < closedY + (openY - closedY) * 0.5f;
    }
    if (isQueue) {
        [self setQueueDrawerOpen:open animated:YES];
    } else {
        [self setStatsDrawerOpen:open animated:YES];
    }
}

- (void)drawerDragged:(UIPanGestureRecognizer *)pan {
    NSInteger index = (pan == self.queueDrag) ? 0 : 1;
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            [self beginDrawerDragAtIndex:index];
            break;
        case UIGestureRecognizerStateChanged:
            [self updateDrawerDragWithTranslation:[pan translationInView:self.view].y];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [self endDrawerDragWithVelocity:[pan velocityInView:self.view].y];
            break;
        default:
            break;
    }
}

// Vertical drag anywhere on the now-playing view: pulls a drawer in from the
// matching edge, or pushes an already-open drawer back out.
- (void)mainVerticalPan:(UIPanGestureRecognizer *)pan {
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
            CGFloat ty = [pan translationInView:self.view].y;
            if (!self.dragIndexResolved) {
                if (fabs(ty) < 8.0f) break;
                [self beginDrawerDragAtIndex:(ty > 0.0f) ? 0 : 1];
                self.dragIndexResolved = YES;
            }
            [self updateDrawerDragWithTranslation:ty];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (self.dragIndexResolved) {
                [self endDrawerDragWithVelocity:[pan velocityInView:self.view].y];
            }
            self.dragIndexResolved = NO;
            break;
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
    button.layer.backgroundColor = [UIColor colorWithWhite:0.85f alpha:1.0f].CGColor;
    button.clipsToBounds = YES;
}

- (void)removeCircleFromButton:(UIButton *)button {
    button.layer.cornerRadius = 0.0f;
    button.layer.borderWidth = 0.0f;
    button.layer.borderColor = NULL;
    button.layer.backgroundColor = NULL;
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
    NSInteger glyphMode = [self isSideBySide] ? 2 : ([self isTallScreen] ? 1 : 0);
    if (glyphMode != self.lastGlyphMode) {
        [self applyTransportImages];
        self.lastGlyphMode = glyphMode;
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

- (void)layoutControls {
    if (self.panning) return;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    BOOL widescreen = [self isWidescreen];

    CGFloat transportH = 40.0f;
    CGFloat smallH = 30.0f;
    CGFloat bottomInset = LTSafeAreaBottom(self.view);
    CGFloat topInset = LTSafeAreaTop(self.view);

    if ([self isSideBySide]) {
        [self layoutPadSideBySideWithWidth:width height:height topInset:topInset bottomInset:bottomInset];
        self.artworkRestingCenter = self.artworkView.center;
        return;
    }

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
    } else {
        CGFloat spacing = 22.0f;
        CGFloat totalWidth = smallH * 2.0f + transportH * 3.0f + spacing * 4.0f;
        CGFloat start = (width - totalWidth) / 2.0f;
        CGFloat smallY = transportY + (transportH - smallH) / 2.0f;

        self.shuffleButton.frame = CGRectMake(start, smallY, smallH, smallH);
        self.prevButton.frame = CGRectMake(start + smallH + spacing, transportY, transportH, transportH);
        self.playButton.frame = CGRectMake(start + smallH + spacing + transportH + spacing, transportY, transportH, transportH);
        self.nextButton.frame = CGRectMake(start + smallH + spacing + (transportH + spacing) * 2.0f, transportY, transportH, transportH);
        self.repeatButton.frame = CGRectMake(start + smallH + spacing + (transportH + spacing) * 3.0f, smallY, smallH, smallH);

        [self removeCircleFromButton:self.playButton];
        [self removeCircleFromButton:self.prevButton];
        [self removeCircleFromButton:self.nextButton];
        [self removeCircleFromButton:self.shuffleButton];
        [self removeCircleFromButton:self.repeatButton];
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
}

#pragma mark - Pages layout

- (void)layoutPages {
    if (self.draggingDrawer) return;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    if (w < 1.0f || h < 1.0f) return;
    CGFloat drawerH = [self drawerHeight];
    self.mainPane.frame = CGRectMake(0, 0, w, h);
    self.queuePane.frame = CGRectMake(0, self.queueDrawerOpen ? 0.0f : -drawerH, w, drawerH);
    self.statsPane.frame = CGRectMake(0, self.statsDrawerOpen ? (h - drawerH) : h, w, drawerH);
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
}

- (void)buildStatsPane {
    self.statsTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statsTitle.text = @"Stats";
    self.statsTitle.font = [UIFont boldSystemFontOfSize:14];
    self.statsTitle.textColor = [UIColor colorWithRed:0.35f green:0.68f blue:1.0f alpha:1.0f];
    self.statsTitle.textAlignment = NSTextAlignmentCenter;
    self.statsTitle.backgroundColor = [UIColor clearColor];
    [self.statsPane addSubview:self.statsTitle];

    self.statsText = [[UITextView alloc] initWithFrame:CGRectZero];
    self.statsText.editable = NO;
    self.statsText.backgroundColor = [UIColor clearColor];
    self.statsText.textColor = [UIColor colorWithWhite:0.95f alpha:1.0f];
    self.statsText.font = [UIFont fontWithName:@"Courier" size:12];
    self.statsText.dataDetectorTypes = UIDataDetectorTypeNone;
    self.statsText.text = @"No track playing yet.\n\nStart playback and its\nnerdy stream stats will\nappear here.";
    self.statsText.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.statsPane addSubview:self.statsText];

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
    CGFloat drawerH = [self drawerHeight];
    CGFloat handleH = 40.0f;
    CGFloat topPad = [self drawerTopPadding];

    self.queueHandle.frame = CGRectMake(0, drawerH - handleH, w, handleH);
    self.queueHeader.frame = CGRectMake(16, 10 + topPad, w - 32, 22);
    self.queueTable.frame = CGRectMake(0, 36 + topPad, w, drawerH - 36 - topPad - handleH);

    self.statsHandle.frame = CGRectMake(0, 0, w, handleH);
    self.statsTitle.frame = CGRectMake(16, handleH + 2, w - 32, 22);
    self.statsText.frame = CGRectMake(16, handleH + 26, w - 32, drawerH - handleH - 34);

    [self centerGripInHandle:self.queueHandle];
    [self centerGripInHandle:self.statsHandle];
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

- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - Refresh

- (void)refreshTrack {
    [self resetArtworkPresentation];
    [self refreshStatsForCurrentTrack];
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
    [self refreshStatsForCurrentTrack];
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
    if ([self artworkBackgroundEnabled]) {
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
    } else {
        [self.backgroundImageView removeFromSuperview];
        self.backgroundImageView = nil;
        [self.scrimView removeFromSuperview];
        self.scrimView = nil;
    }
}

- (void)setArtworkImage:(UIImage *)image forVideoId:(NSString *)videoId {
    if (!image) return;
    self.artworkView.image = image;
    if (![self artworkBackgroundEnabled]) return;
    UIImage *blurred = [self.blurCache objectForKey:videoId];
    if (blurred) {
        self.backgroundImageView.image = blurred;
        return;
    }
    __weak LTPlayerViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        UIImage *result = [LTGraphics blurredImageFromImage:image];
        if (!result) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            LTPlayerViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            NSString *currentId = [[LTPlayerController sharedController] currentTrack].videoId;
            if (videoId.length && [videoId isEqualToString:currentId]) {
                [strongSelf.blurCache setObject:result forKey:videoId];
                strongSelf.backgroundImageView.image = result;
                LTLog(@"PLAYER_BG bounds=%.0f x %.0f frame=%.0f,%.0f imgSz=%.0f x %.0f",
                      strongSelf.view.bounds.size.width, strongSelf.view.bounds.size.height,
                      strongSelf.backgroundImageView.frame.size.width, strongSelf.backgroundImageView.frame.size.height,
                      result.size.width, result.size.height);
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

    if ([controller isPlaying]) {
        [self.playButton setImage:[UIImage imageNamed:@"IcoPause"] forState:UIControlStateNormal];
    } else {
        [self.playButton setImage:[UIImage imageNamed:@"IcoPlay"] forState:UIControlStateNormal];
    }

    self.shuffleButton.selected = controller.shuffleEnabled;
    switch (controller.repeatMode) {
        case LTRepeatModeOff:
            [self.repeatButton setImage:[UIImage imageNamed:@"IcoRepeat"] forState:UIControlStateNormal];
            [self.repeatButton setImage:[UIImage imageNamed:@"IcoRepeatBlue"] forState:UIControlStateSelected];
            self.repeatButton.selected = NO;
            break;
        case LTRepeatModeAll:
            [self.repeatButton setImage:[UIImage imageNamed:@"IcoRepeat"] forState:UIControlStateNormal];
            [self.repeatButton setImage:[UIImage imageNamed:@"IcoRepeatBlue"] forState:UIControlStateSelected];
            self.repeatButton.selected = YES;
            break;
        case LTRepeatModeOne:
            [self.repeatButton setImage:[UIImage imageNamed:@"IcoRepeatOne"] forState:UIControlStateNormal];
            [self.repeatButton setImage:[UIImage imageNamed:@"IcoRepeatOneBlue"] forState:UIControlStateSelected];
            self.repeatButton.selected = YES;
            break;
    }
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
        [self refreshStatsForCurrentTrack];
    }
}

- (NSString *)formatTime:(NSTimeInterval)time {
    if (time < 0 || isnan(time)) time = 0;
    NSInteger seconds = (NSInteger)time;
    return [NSString stringWithFormat:@"%d:%02d", (int)(seconds / 60), (int)(seconds % 60)];
}

#pragma mark - Timer

- (void)startTimer {
    [self stopTimer];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
}

- (void)stopTimer {
    [self.timer invalidate];
    self.timer = nil;
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
    [self refreshStatsForCurrentTrack];
}

- (void)queueDidChange:(NSNotification *)notification {
    [self refreshControls];
    [self reloadQueue];
    [self refreshStatsForCurrentTrack];
}

#pragma mark - Stats

- (void)refreshStatsForCurrentTrack {
    if (!self.statsText) return;
    CGPoint offset = self.statsText.contentOffset;
    LTTrack *track = [[LTPlayerController sharedController] currentTrack];
    if (!track) {
        self.statsText.text = @"Nothing playing.\n\nStart playback and its\nnerdy stream stats will\nappear here.";
    } else {
        self.statsText.text = [self statsTextForTrack:track];
    }
    self.statsText.contentOffset = offset;
}

- (NSString *)statsTextForTrack:(LTTrack *)track {
    LTPlayerController *controller = [LTPlayerController sharedController];
    NSDictionary *fmt = [[LTYouTubeClient sharedClient] lastFormatInfo];
    NSString *fmtVideoId = [fmt objectForKey:@"videoId"];
    BOOL fmtMatches = (track.videoId.length && [fmtVideoId isEqualToString:track.videoId]);

    NSMutableString *s = [NSMutableString string];

    [s appendString:@"-- TRACK --\n"];
    [s appendString:[self statsLine:@"Title" value:track.title]];
    [s appendString:[self statsLine:@"Artist" value:track.artist]];
    [s appendString:[self statsLine:@"Album" value:track.album]];
    [s appendString:[self statsLine:@"Video ID" value:track.videoId]];

    NSTimeInterval dur = [controller duration];
    if (dur <= 0) dur = track.duration;
    NSString *durationValue = [NSString stringWithFormat:@"%@ / %@",
                               [self formatTime:[controller currentTime]],
                               [self formatTime:dur]];
    [s appendString:[self statsLine:@"Elapsed" value:durationValue]];

    [s appendString:@"\n-- STREAM --\n"];
    if (fmtMatches) {
        NSString *mime = [fmt objectForKey:@"mimeType"] ?: @"";
        [s appendString:[self statsLine:@"Codec" value:[self codecDescriptionForMimeType:mime]]];
        NSInteger kbps = [self bitrateKbpsFromFormat:fmt fallback:[controller audioBitrateKbps]];
        [s appendString:[self statsLine:@"Bitrate" value:[NSString stringWithFormat:@"%d kbps", (int)kbps]]];
        NSString *sample = [fmt objectForKey:@"audioSampleRate"];
        if (sample.length) {
            [s appendString:[self statsLine:@"Sample" value:[NSString stringWithFormat:@"%@ Hz", sample]]];
        }
        NSNumber *itag = [fmt objectForKey:@"itag"];
        if (itag) {
            [s appendString:[self statsLine:@"Itag" value:[NSString stringWithFormat:@"%d", [itag intValue]]]];
        }
        BOOL muxed = [[fmt objectForKey:@"muxed"] boolValue];
        [s appendString:[self statsLine:@"Format" value:muxed ? @"video+audio" : @"audio-only"]];
        NSString *client = [fmt objectForKey:@"clientName"];
        if (client.length) {
            [s appendString:[self statsLine:@"Source" value:client]];
        }
    } else {
        NSInteger localKbps = [controller audioBitrateKbps];
        if (localKbps > 0) {
            [s appendString:[self statsLine:@"Bitrate" value:[NSString stringWithFormat:@"%d kbps", (int)localKbps]]];
        }
        [s appendString:[self statsLine:@"Format" value:@"local / cached"]];
    }

    [s appendString:@"\n-- SESSION --\n"];
    NSString *source = [controller queueSourceName] ?: @"";
    [s appendString:[self statsLine:@"Queue src" value:source]];
    NSInteger queued = (NSInteger)controller.queue.count;
    if (queued > 0) {
        NSString *pos = [NSString stringWithFormat:@"%d of %d", (int)controller.currentIndex + 1, (int)queued];
        [s appendString:[self statsLine:@"Position" value:pos]];
    }
    NSString *repeat = @"Off";
    if (controller.repeatMode == LTRepeatModeAll) repeat = @"All";
    else if (controller.repeatMode == LTRepeatModeOne) repeat = @"One";
    [s appendString:[self statsLine:@"Repeat" value:repeat]];
    [s appendString:[self statsLine:@"Shuffle" value:controller.shuffleEnabled ? @"On" : @"Off"]];

    [s appendString:@"\n-- DEVICE --\n"];
    [s appendString:[self statsLine:@"Model" value:[self deviceModelName]]];
    [s appendString:[self statsLine:@"iOS" value:[UIDevice currentDevice].systemVersion]];
    [s appendString:[self statsLine:@"Screen" value:[self screenDescription]]];
    [s appendString:[self statsLine:@"App" value:[self appVersionDescription]]];

    return s;
}

- (NSString *)statsLine:(NSString *)label value:(NSString *)value {
    NSString *v = value.length ? value : @"\u2014";
    NSMutableString *padded = [NSMutableString stringWithString:label];
    while (padded.length < 11) [padded appendString:@" "];
    return [NSString stringWithFormat:@"%@ %@\n", padded, v];
}

- (NSString *)codecDescriptionForMimeType:(NSString *)mime {
    NSString *lower = [mime lowercaseString];
    BOOL video = ([lower rangeOfString:@"video/"].location != NSNotFound);
    BOOL mp4 = ([lower rangeOfString:@"mp4"].location != NSNotFound);
    BOOL webm = ([lower rangeOfString:@"webm"].location != NSNotFound);
    NSString *container = mp4 ? @"MP4" : (webm ? @"WebM" : (video ? @"MP4" : @"?"));

    NSString *codec = @"";
    NSRange range = [lower rangeOfString:@"codecs="];
    if (range.location != NSNotFound) {
        NSString *rest = [lower substringFromIndex:range.location + 7];
        rest = [rest stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\" "]];
        NSArray *parts = [rest componentsSeparatedByString:@","];
        if (parts.count) codec = [[parts objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    NSString *friendly = codec;
    if ([codec isEqualToString:@"mp4a.40.2"]) friendly = @"AAC";
    else if ([codec isEqualToString:@"mp4a.40.5"]) friendly = @"HE-AAC";
    else if ([codec isEqualToString:@"opus"]) friendly = @"Opus";
    else if ([codec isEqualToString:@"vorbis"]) friendly = @"Vorbis";
    else if (codec.length) friendly = codec;
    else friendly = @"?";

    return [NSString stringWithFormat:@"%@ / %@", container, friendly];
}

- (NSInteger)bitrateKbpsFromFormat:(NSDictionary *)fmt fallback:(NSInteger)fallback {
    NSNumber *bps = [fmt objectForKey:@"bitrate"];
    if ([bps isKindOfClass:[NSNumber class]] && [bps integerValue] > 0) {
        return (NSInteger)([bps doubleValue] / 1000.0 + 0.5);
    }
    return fallback;
}

- (NSString *)deviceModelName {
    struct utsname sysInfo;
    if (uname(&sysInfo) == 0) {
        NSString *machine = [NSString stringWithUTF8String:sysInfo.machine];
        if (machine.length) return machine;
    }
    return [[UIDevice currentDevice] model];
}

- (NSString *)screenDescription {
    UIScreen *screen = [UIScreen mainScreen];
    return [NSString stringWithFormat:@"%d x %d @%.0fx",
            (int)screen.bounds.size.width, (int)screen.bounds.size.height, (double)screen.scale];
}

- (NSString *)appVersionDescription {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *shortVer = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?";
    return [NSString stringWithFormat:@"v%@ (build %@)", shortVer, build];
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
    }
    LTPlayerController *controller = [LTPlayerController sharedController];
    LTTrack *track = [[controller queue] objectAtIndex:(NSUInteger)indexPath.row];
    NSInteger idx = (NSInteger)indexPath.row;
    cell.imageView.image = nil;
    if (idx == controller.currentIndex) {
        cell.imageView.image = [self scaledQueueIcon:[UIImage imageNamed:@"IcoPlay"]];
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
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        LTLog(@"PLAYER_PAGE delete row %d", (int)indexPath.row);
        [[LTPlayerController sharedController] removeTrackAtIndex:indexPath.row];
        [self reloadQueue];
    }
}

@end
