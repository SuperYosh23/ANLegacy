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
#import "LTLog.h"

@interface LTPlayerViewController () <UIScrollViewDelegate, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIScrollView *pageScrollView;
@property (nonatomic, strong) UIPanGestureRecognizer *swipePan;
@property (nonatomic, strong) UIView *mainPane;
@property (nonatomic, strong) UIView *queuePane;
@property (nonatomic, strong) UIView *statsPane;
@property (nonatomic, strong) UILabel *queueHeader;
@property (nonatomic, strong) UITableView *queueTable;
@property (nonatomic, strong) UILabel *statsTitle;
@property (nonatomic, strong) UITextView *statsText;
@property (nonatomic, strong) UILabel *pagesHint;
@property (nonatomic, assign) NSInteger pagerPage;
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
@property (nonatomic, assign) BOOL scrubbing;
@property (nonatomic, assign) BOOL panning;
@property (nonatomic, assign) CGFloat panBaseX;
@property (nonatomic, assign) BOOL panCommitted;
@property (nonatomic, assign) NSInteger panSwipeDir;
@end

@implementation LTPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    self.title = @"Now Playing";
    self.view.backgroundColor = [UIColor colorWithWhite:0.15f alpha:1.0f];
    LTLog(@"PLAYER_VC bounds=%d x %d", (int)self.view.bounds.size.width, (int)self.view.bounds.size.height);

    self.blurCache = [[NSCache alloc] init];
    [self applyArtworkBackgroundPref];

    // Vertical pager: queue (top), main (middle), stats (bottom).
    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;
    self.pageScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    self.pageScrollView.pagingEnabled = YES;
    self.pageScrollView.directionalLockEnabled = YES;
    self.pageScrollView.showsHorizontalScrollIndicator = NO;
    self.pageScrollView.showsVerticalScrollIndicator = NO;
    self.pageScrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.pageScrollView];

    self.queuePane = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    self.queuePane.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.85f];
    [self.pageScrollView addSubview:self.queuePane];

    self.mainPane = [[UIView alloc] initWithFrame:CGRectMake(0, H, W, H)];
    self.mainPane.backgroundColor = [UIColor clearColor];
    [self.pageScrollView addSubview:self.mainPane];

    self.statsPane = [[UIView alloc] initWithFrame:CGRectMake(0, H * 2.0f, W, H)];
    self.statsPane.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.85f];
    [self.pageScrollView addSubview:self.statsPane];

    self.pageScrollView.contentSize = CGSizeMake(W, H * 3.0f);
    self.pageScrollView.contentOffset = CGPointMake(0, H);
    self.pagerPage = 1;

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
    self.pagesHint.font = [UIFont systemFontOfSize:10];
    self.pagesHint.textColor = [UIColor colorWithWhite:0.85f alpha:0.85f];
    self.pagesHint.backgroundColor = [UIColor clearColor];
    [self.mainPane addSubview:self.pagesHint];

    [self layoutControls];
    [self buildQueuePane];
    [self buildStatsPane];
    [self layoutPages];
    [self setupSwipeGestures];
}

- (void)setupSwipeGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.minimumNumberOfTouches = 1;
    pan.delegate = self;
    self.swipePan = pan;
    [self.mainPane addGestureRecognizer:pan];
    [self.pageScrollView.panGestureRecognizer requireGestureRecognizerToFail:pan];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.swipePan) {
        CGPoint v = [self.swipePan velocityInView:self.mainPane];
        return fabs(v.x) > fabs(v.y);
    }
    return YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *view = self.view;
    CGPoint translation = [pan translationInView:view];
    CGFloat width = view.bounds.size.width;
    CGFloat maxDrag = width * 0.5f;

    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            self.panning = YES;
            self.panBaseX = width / 2.0f;
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
            BOOL commit = (fabs(tx) > width * 0.18f) || velocity > 750.0f;
            if (commit && self.panSwipeDir != 0) {
                self.panCommitted = YES;
                CGFloat dirOff = (self.panSwipeDir > 0) ? 1.0f : -1.0f;
                CGFloat offX = (width / 2.0f) * dirOff + self.artworkView.bounds.size.width * dirOff;
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

- (void)resetArtworkPresentation {
    self.panBaseX = self.view.bounds.size.width / 2.0f;
    self.artworkView.center = CGPointMake(self.panBaseX, self.artworkView.center.y);
    self.artworkView.transform = CGAffineTransformIdentity;
    self.artworkView.alpha = 1.0f;
    self.incomingArtworkView.center = CGPointMake(self.panBaseX, self.artworkView.center.y);
    self.incomingArtworkView.transform = CGAffineTransformIdentity;
    self.incomingArtworkView.alpha = 0.0f;
    self.incomingArtworkView.image = nil;
    self.panSwipeDir = 0;
}

- (UIButton *)makeIconButton:(NSString *)imageName selectedImage:(NSString *)selectedImageName action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:[UIImage imageNamed:imageName] forState:UIControlStateNormal];
    [button setImage:[UIImage imageNamed:selectedImageName] forState:UIControlStateSelected];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.backgroundImageView) self.backgroundImageView.frame = self.view.bounds;
    if (self.scrimView) self.scrimView.frame = self.view.bounds;
    [self layoutControls];
    [self layoutPages];
    [self layoutPageSubviews];
}- (BOOL)isWidescreen {
    if ([LTDebugSettings forceNonWidescreen]) return NO;
    if ([LTDebugSettings forceWidescreen]) return YES;
    return ([[UIScreen mainScreen] bounds].size.height >= 568.0f);
}

- (void)layoutControls {
    if (self.panning) return;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    BOOL widescreen = [self isWidescreen];

    CGFloat transportH = 40.0f;
    CGFloat smallH = 30.0f;
    CGFloat bottomPad = widescreen ? 9.0f : 4.0f;
    CGFloat transportY = height - bottomPad - transportH;
    CGFloat sliderH = 22.0f;
    CGFloat sliderY = transportY - 8.0f - sliderH;
    CGFloat timeY = sliderY - 4.0f - 16.0f;

    if (!widescreen) {
        transportY -= 5.0f;
    }

    if (widescreen) {
        self.bitrateLabel.frame = CGRectMake(16, height - 20, 90, 14);
        CGFloat topPad = 24.0f;
        self.sourceLabel.hidden = NO;
        self.sourceLabel.textAlignment = NSTextAlignmentCenter;
        self.sourceLabel.frame = CGRectMake(12, topPad + 2.0f, width - 24, 24);

        CGFloat titleH = 22.0f;
        CGFloat artistH = 16.0f;
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
    } else {
        self.sourceLabel.hidden = YES;
        self.bitrateLabel.frame = CGRectMake(12, 12, 70, 14);
        CGFloat titleY = 10.0f;
        CGFloat titleH = 22.0f;
        self.titleLabel.frame = CGRectMake(12, titleY, width - 24, titleH);
        self.artistLabel.frame = CGRectMake(12, titleY + titleH + 2.0f, width - 24, 16);

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

    CGFloat spacing = 22.0f;
    CGFloat totalWidth = smallH * 2.0f + transportH * 3.0f + spacing * 4.0f;
    CGFloat start = (width - totalWidth) / 2.0f;
    CGFloat smallY = transportY + (transportH - smallH) / 2.0f;

    self.shuffleButton.frame = CGRectMake(start, smallY, smallH, smallH);
    self.prevButton.frame = CGRectMake(start + smallH + spacing, transportY, transportH, transportH);
    self.playButton.frame = CGRectMake(start + smallH + spacing + transportH + spacing, transportY, transportH, transportH);
    self.nextButton.frame = CGRectMake(start + smallH + spacing + (transportH + spacing) * 2.0f, transportY, transportH, transportH);
    self.repeatButton.frame = CGRectMake(start + smallH + spacing + (transportH + spacing) * 3.0f, smallY, smallH, smallH);
    self.pagesHint.hidden = ![self isWidescreen];
    self.pagesHint.frame = CGRectMake(0, 2, width, 14);
}

#pragma mark - Pages layout

- (void)layoutPages {
    if (!self.pageScrollView) return;
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    if (w < 1.0f || h < 1.0f) return;
    self.pageScrollView.frame = self.view.bounds;
    self.pageScrollView.contentSize = CGSizeMake(w, h * 3.0f);
    self.queuePane.frame = CGRectMake(0, 0, w, h);
    self.mainPane.frame = CGRectMake(0, h, w, h);
    self.statsPane.frame = CGRectMake(0, h * 2.0f, w, h);
    if (!self.pageScrollView.dragging && !self.pageScrollView.decelerating) {
        self.pageScrollView.contentOffset = CGPointMake(0, h * (CGFloat)self.pagerPage);
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    CGFloat h = self.view.bounds.size.height;
    if (h > 1.0f) {
        NSInteger page = (NSInteger)(floor((scrollView.contentOffset.y + h * 0.5f) / h));
        self.pagerPage = MIN(2, MAX(0, page));
    }
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
}

- (void)layoutPageSubviews {
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    self.queueHeader.frame = CGRectMake(16, 10, w - 32, 22);
    self.queueTable.frame = CGRectMake(0, 36, w, h - 36);

    self.statsTitle.frame = CGRectMake(16, 10, w - 32, 22);
    self.statsText.frame = CGRectMake(16, 38, w - 32, h - 52);
}

- (void)revealQueue {
    self.pagerPage = 0;
    [self.pageScrollView setContentOffset:CGPointMake(0, 0) animated:YES];
}

- (void)revealNowPlaying {
    self.pagerPage = 1;
    CGFloat h = self.view.bounds.size.height;
    [self.pageScrollView setContentOffset:CGPointMake(0, h) animated:YES];
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
}

- (void)refreshSourceLabel {
    self.sourceLabel.text = [[LTPlayerController sharedController] queueSourceName] ?: @"";
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
    if ([controller isPlaying]) {
        [self.playButton setImage:[UIImage imageNamed:@"IcoPause"] forState:UIControlStateNormal];
    } else {
        [self.playButton setImage:[UIImage imageNamed:@"IcoPlay"] forState:UIControlStateNormal];
    }
    if ([controller isLoading]) {
        [self.spinner startAnimating];
    } else {
        [self.spinner stopAnimating];
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
    if (self.pagerPage == 2) {
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
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellId];
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
