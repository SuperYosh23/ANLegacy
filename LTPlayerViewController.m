#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import "LTPlayerViewController.h"
#import "LTPlayerController.h"
#import "LTQueueViewController.h"
#import "LTYouTubeClient.h"
#import "LTPlaylistStore.h"
#import "LTGraphics.h"
#import "LTDebugSettings.h"
#import "LTLog.h"

@interface LTPlayerViewController ()
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
@property (nonatomic, strong) UIButton *queueButton;
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

    self.incomingArtworkView = [[UIImageView alloc] init];
    self.incomingArtworkView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    self.incomingArtworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.incomingArtworkView.clipsToBounds = YES;
    self.incomingArtworkView.alpha = 0.0f;
    [self.view addSubview:self.incomingArtworkView];

    self.artworkView = [[UIImageView alloc] init];
    self.artworkView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    [self.view addSubview:self.artworkView];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [self.view addSubview:self.spinner];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.titleLabel];

    self.artistLabel = [[UILabel alloc] init];
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.font = [UIFont systemFontOfSize:13];
    self.artistLabel.textColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    self.artistLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.artistLabel];

    self.sourceLabel = [[UILabel alloc] init];
    self.sourceLabel.textAlignment = NSTextAlignmentLeft;
    self.sourceLabel.font = [UIFont boldSystemFontOfSize:17];
    self.sourceLabel.textColor = [UIColor colorWithWhite:0.9f alpha:1.0f];
    self.sourceLabel.backgroundColor = [UIColor clearColor];
    self.sourceLabel.text = @"";
    [self.view addSubview:self.sourceLabel];

    self.bitrateLabel = [[UILabel alloc] init];
    self.bitrateLabel.textAlignment = NSTextAlignmentLeft;
    self.bitrateLabel.font = [UIFont systemFontOfSize:11];
    self.bitrateLabel.textColor = [UIColor colorWithWhite:0.6f alpha:1.0f];
    self.bitrateLabel.backgroundColor = [UIColor clearColor];
    self.bitrateLabel.text = @"";
    [self.view addSubview:self.bitrateLabel];

    self.elapsedLabel = [[UILabel alloc] init];
    self.elapsedLabel.font = [UIFont systemFontOfSize:11];
    self.elapsedLabel.textColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    self.elapsedLabel.backgroundColor = [UIColor clearColor];
    self.elapsedLabel.text = @"0:00";
    [self.view addSubview:self.elapsedLabel];

    self.remainingLabel = [[UILabel alloc] init];
    self.remainingLabel.font = [UIFont systemFontOfSize:11];
    self.remainingLabel.textColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    self.remainingLabel.backgroundColor = [UIColor clearColor];
    self.remainingLabel.textAlignment = NSTextAlignmentRight;
    self.remainingLabel.text = @"0:00";
    [self.view addSubview:self.remainingLabel];

    self.progressSlider = [[UISlider alloc] init];
    [self.progressSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchedUp:) forControlEvents:UIControlEventTouchUpInside];
    [self.progressSlider addTarget:self action:@selector(sliderTouchedUp:) forControlEvents:UIControlEventTouchUpOutside];
    [self.view addSubview:self.progressSlider];

    self.prevButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.prevButton setImage:[UIImage imageNamed:@"IcoPrev"] forState:UIControlStateNormal];
    [self.prevButton addTarget:self action:@selector(prevTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.prevButton];

    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.playButton setImage:[UIImage imageNamed:@"IcoPlay"] forState:UIControlStateNormal];
    [self.playButton addTarget:self action:@selector(playTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playButton];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.nextButton setImage:[UIImage imageNamed:@"IcoNext"] forState:UIControlStateNormal];
    [self.nextButton addTarget:self action:@selector(nextTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextButton];

    self.shuffleButton = [self makeIconButton:@"IcoShuffle" selectedImage:@"IcoShuffleBlue" action:@selector(shuffleTapped:)];
    [self.view addSubview:self.shuffleButton];

    self.repeatButton = [self makeIconButton:@"IcoRepeat" selectedImage:@"IcoRepeatBlue" action:@selector(repeatTapped:)];
    [self.view addSubview:self.repeatButton];

    self.queueButton = [self makeIconButton:@"IcoQueue" selectedImage:@"IcoQueueBlue" action:@selector(queueTapped:)];
    [self.view addSubview:self.queueButton];

    [self layoutControls];
    [self setupSwipeGestures];
}

- (void)setupSwipeGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.minimumNumberOfTouches = 1;
    [self.view addGestureRecognizer:pan];
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
        CGFloat queueSize = 30.0f;
        self.queueButton.frame = CGRectMake(width - queueSize - 10, topPad, queueSize, queueSize);
        self.sourceLabel.hidden = NO;
        self.sourceLabel.frame = CGRectMake(12, topPad + 2.0f, width - queueSize - 28, 24);

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
        self.queueButton.hidden = NO;
        self.sourceLabel.hidden = YES;
        self.bitrateLabel.frame = CGRectMake(12, 12, 70, 14);
        CGFloat titleY = 10.0f;
        CGFloat titleH = 22.0f;
        self.titleLabel.frame = CGRectMake(12, titleY, width - 24, titleH);
        self.artistLabel.frame = CGRectMake(12, titleY + titleH + 2.0f, width - 24, 16);

        CGFloat queueSize = 30.0f;
        self.queueButton.frame = CGRectMake(width - queueSize - 8, titleY + (titleH - queueSize) / 2.0f, queueSize, queueSize);

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
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
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
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopTimer];
}

#pragma mark - Refresh

- (void)refreshTrack {
    [self resetArtworkPresentation];
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

- (void)queueTapped:(id)sender {
    LTQueueViewController *queue = [[LTQueueViewController alloc] init];
    [self.navigationController pushViewController:queue animated:YES];
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
}

- (void)queueDidChange:(NSNotification *)notification {
    [self refreshControls];
}

@end
