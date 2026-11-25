#import <QuartzCore/QuartzCore.h>
#import "LTArtworkBackground.h"
#import <CoreGraphics/CoreGraphics.h>
#import <MediaPlayer/MediaPlayer.h>
#import <sys/utsname.h>
#import "LTPlayerViewController.h"
#import "LTTheme.h"
#import "LTCardControls.h"
#import "LTPlayerController.h"
#import "LTQueueViewController.h"
#import "LTYouTubeClient.h"
#import "LTPlaylistStore.h"
#import "LTLucideIcons.h"
#import "LTTransitionSettings.h"
#import "LTGraphics.h"
#import "LTDebugSettings.h"
#import "LTOneHandedMode.h"
#import "LTLog.h"
#import "LTSafeArea.h"
#import "LTSimpleCell.h"
#import "LTHaptics.h"
#import "LTPeekCoordinator.h"
#import "LTArtworkPeekViewController.h"
#import "LTLyricsSettings.h"
#import "LTLyricsPaperView.h"
#import "LTPlaylistPicker.h"
#import "LTPlaylistStore.h"
#import "LTThemedTableView.h"
#import <math.h>

// The bottom info drawer (Lyrics / General) is disabled on iOS 5 and earlier:
// it cannot be pulled up there at all. Keep the gate in one place so every
// gesture, tap and programmatic open obeys it.
static BOOL LTInfoDrawerAllowed(void) {
    return [[[UIDevice currentDevice] systemVersion] integerValue] > 5;
}

// iOS 4 occasionally cancels a short, stationary touch on a UIButton before
// TouchUpInside is delivered. The symptom is a visible press halo with no action:
// the button gets TouchDown, then UIKit sends touchesCancelled. Normal touches
// are unaffected, so a quick tap silently does nothing. This subclass keeps the
// geometry/time of the initial touch and, if the system cancels a genuine tap,
// delivers TouchUpInside itself so the button's action still runs.
@interface LTTapResilientButton : UIButton {
@private
    CFAbsoluteTime _ltDownTime;
    CGPoint _ltDownPoint;
    BOOL _ltTracking;
}
@end

@implementation LTTapResilientButton

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (touch) {
        _ltDownTime = CFAbsoluteTimeGetCurrent();
        _ltDownPoint = [touch locationInView:self];
        _ltTracking = YES;
    }
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    BOOL wasTap = NO;
    if (touch && _ltTracking) {
        CFAbsoluteTime elapsed = CFAbsoluteTimeGetCurrent() - _ltDownTime;
        CGPoint p = [touch locationInView:self];
        CGFloat dx = p.x - _ltDownPoint.x;
        CGFloat dy = p.y - _ltDownPoint.y;
        CGFloat moved = sqrtf(dx * dx + dy * dy);
        // A real tap is short and stays essentially in place. A cancelled drag,
        // swipe, or system interruption is longer or moves further and is left
        // alone so it cannot trigger an action by accident.
        if (elapsed >= 0.0 && elapsed <= 0.5 &&
            moved <= 12.0f && CGRectContainsPoint(self.bounds, p)) {
            wasTap = YES;
        }
    }
    _ltTracking = NO;
    [super touchesCancelled:touches withEvent:event];
    if (wasTap) [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}

@end

static BOOL sHasShownSwipeHint = NO;

@interface LTPlayerViewController () <UIScrollViewDelegate, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate, UIActionSheetDelegate>
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
@property (nonatomic, strong) LTThemedTableView *queueTable;
// The lyrics drawer is now the "info" drawer and carries more than one page, so
// the old static title is replaced by a segmented control that switches between
// them. Both pages are plain views laid out with frames, matching the rest of
// this controller, rather than child view controllers.
@property (nonatomic, strong) UISegmentedControl *infoPageControl;
@property (nonatomic, strong) UIScrollView *generalScroll;
// A pan rather than a swipe recogniser, so the pages can track the finger
// instead of cutting once the gesture completes.
@property (nonatomic, strong) UIPanGestureRecognizer *infoPagePan;
// Every page-pan instance. One per page scroll view plus one on the pane, because a
// touch over text is offered to the scroll view first. The delegate compares
// against this set rather than the single pane instance.
@property (nonatomic, strong) NSMutableSet *infoPagePans;
@property (nonatomic, assign) CGRect infoPageBaseFrame;
// Video page
@property (nonatomic, assign) NSInteger infoPageDragFrom;
@property (nonatomic, assign) NSInteger infoPageNeighbor;
@property (nonatomic, assign) BOOL infoPageSettling;
// The page actually being displayed. Deliberately NOT read back from
// infoPageControl.selectedSegmentIndex: UIControl has already updated that by the
// time UIControlEventValueChanged is delivered, so treating it as the source of
// truth made every tap compare equal to the current page and return early -- which
// silently skipped the refresh and left the Comments page empty forever.
@property (nonatomic, assign) NSInteger infoPageCurrent;
// Rows held back because the scroll view had no width yet when they arrived.
@property (nonatomic, strong) NSDictionary *generalPending;
// YES once a YouTube fetch has completed for the current track, successfully or
// not. Tracked separately from generalInfo so a page showing only local metadata is
// not mistaken for a page still waiting to load.
@property (nonatomic, assign) BOOL generalFetched;
// Guards against the several refresh entry points (track change, tab open,
// state change) starting a second identical fetch chain while the first is
// still in flight.
@property (nonatomic, assign) BOOL generalFetching;
@property (nonatomic, strong) UIImageView *generalAvatar;
@property (nonatomic, copy) NSString *generalVideoId;
@property (nonatomic, strong) NSDictionary *generalInfo;
@property (nonatomic, strong) UIScrollView *lyricsScroll;
// The sheet of paper the lyrics sit on, on the systems whose chrome was
// skeuomorphic.
@property (nonatomic, strong) LTLyricsPaperView *lyricsPaper;
@property (nonatomic, strong) NSMutableArray *lyricLabelViews;
@property (nonatomic, copy) NSArray *lyricLines;
// The plain, untimed lyrics, kept so they can be laid out again for a drawer
// that is a different width.
@property (nonatomic, copy) NSString *lyricsPlainText;
// The width the lyrics were last laid out for.
@property (nonatomic, assign) CGFloat lyricsLayoutWidth;
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
// A top-to-bottom fade over the blurred artwork, so the white labels and the
// scrubber stay readable over any cover without flattening the whole image.
@property (nonatomic, strong) CAGradientLayer *gradientScrim;
// One white pill behind the whole five-button transport row, used only in the
// layouts that are neither iPad nor a notched phone. The others keep a disc
// behind each key.
@property (nonatomic, strong) UIView *transportBar;
// Soft halo shown behind whichever transport key is being held down. Kept as a
// sibling view rather than a layer shadow because the keys clip to bounds for
// their rounded backgrounds, which would cut a shadow off at the edge.
@property (nonatomic, strong) UIView *pressGlow;
// Top-right utility row: AirPlay route picker and add-to-playlist.
@property (nonatomic, strong) UIButton *airPlayButton;
@property (nonatomic, strong) UIButton *playlistButton;
@property (nonatomic, strong) MPVolumeView *routeVolumeView;
// Separate small pill behind the two utility keys in landscape, where they sit
// apart from the transport row.
@property (nonatomic, strong) UIView *utilityBar;
@property (nonatomic, strong) NSCache *blurCache;
@property (nonatomic, strong) NSCache *paletteCache;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) LTPeekCoordinator *artworkPeek;
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
@property (nonatomic, strong) UIButton *stationMenuButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIView *spinnerBackdrop;
@property (nonatomic, strong) UIView *customMenuBackdrop;
@property (nonatomic, strong) UIView *customMenuContainer;
// Track currently on screen, so the artwork slide only plays when the cover
// actually changes and not when the high-res replaces the thumbnail.
@property (nonatomic, copy) NSString *artworkVideoId;
@property (nonatomic, assign) NSInteger artworkTrackIndex;
// refreshTrack blanks the cover so a stale one is never shown while the next
// track loads. Kept aside so the arriving cover can slide it out instead of
// fading up from blank.
@property (nonatomic, strong) UIImage *outgoingArtworkImage;
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
@property (nonatomic, assign) BOOL swipeTransitionInProgress;
@property (nonatomic, assign) NSInteger lastGlyphMode;
@property (nonatomic, assign) CGFloat lastDebugPW;
@property (nonatomic, assign) CGFloat lastDebugPH;
@property (nonatomic, assign) BOOL lastDebugDock;
@end

@implementation LTPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = @"Now Playing";
    self.view.backgroundColor = [LTTheme background];
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
    self.queuePane.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.queuePane];

    self.statsPane = [[UIView alloc] initWithFrame:CGRectMake(0, H, W, drawerH)];
    self.statsPane.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.statsPane];

    [self applyDrawerBackgroundTo:self.queuePane];
    [self applyDrawerBackgroundTo:self.statsPane];

    self.queueDrawerOpen = NO;
    self.statsDrawerOpen = NO;

    self.incomingArtworkView = [[UIImageView alloc] init];
    self.incomingArtworkView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    self.incomingArtworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.incomingArtworkView.clipsToBounds = YES;
    // Matches the resting artwork's rounding, so the slide in does not change
    // the corner shape mid-animation.
    self.incomingArtworkView.layer.cornerRadius = 8.0f;
    self.incomingArtworkView.alpha = 0.0f;
    [self.mainPane addSubview:self.incomingArtworkView];

    self.artworkView = [[UIImageView alloc] init];
    self.artworkView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.cornerRadius = 8.0f;
    // Needed so the peek gesture can start on the artwork. The pan gestures
    // live on mainPane, an ancestor, so they still receive these touches.
    self.artworkView.userInteractionEnabled = YES;
    [self.mainPane addSubview:self.artworkView];

    // Peek the artwork: a large, high-resolution copy of the current cover.
    // The track is read at peek time so it always matches what is playing.
    __unsafe_unretained LTPlayerViewController *peekSelf = self;
    self.artworkPeek = [[LTPeekCoordinator alloc] initWithOwner:self
                                                    sourceView:self.artworkView
                                                 peekProvider:^UIViewController *(CGPoint location) {
        LTTrack *track = [LTPlayerController sharedController].currentTrack;
        if (!track) return nil;
        return [[LTArtworkPeekViewController alloc] initWithTrack:track
                                                           image:peekSelf.artworkView.image];
    } commit:nil];
    [self.artworkPeek registerPreview];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinnerBackdrop = [[UIView alloc] initWithFrame:CGRectZero];
    self.spinnerBackdrop.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.55f];
    self.spinnerBackdrop.hidden = YES;
    [self.mainPane addSubview:self.spinnerBackdrop];
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

    self.prevButton = [LTTapResilientButton buttonWithType:UIButtonTypeCustom];
    [self.prevButton setImage:[UIImage imageNamed:@"IcoPrev"] forState:UIControlStateNormal];
    [self.prevButton addTarget:self action:@selector(prevTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPane addSubview:self.prevButton];

    self.playButton = [LTTapResilientButton buttonWithType:UIButtonTypeCustom];
    [self.playButton setImage:[UIImage imageNamed:@"IcoPlay"] forState:UIControlStateNormal];
    [self.playButton addTarget:self action:@selector(playTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPane addSubview:self.playButton];

    self.nextButton = [LTTapResilientButton buttonWithType:UIButtonTypeCustom];
    [self.nextButton setImage:[UIImage imageNamed:@"IcoNext"] forState:UIControlStateNormal];
    [self.nextButton addTarget:self action:@selector(nextTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPane addSubview:self.nextButton];

    self.stationMenuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.stationMenuButton setTitle:@"⋯" forState:UIControlStateNormal];
    self.stationMenuButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    [self.stationMenuButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [self.stationMenuButton addTarget:self action:@selector(stationMenuTapped:) forControlEvents:UIControlEventTouchUpInside];
    self.stationMenuButton.hidden = YES;
    [self.mainPane addSubview:self.stationMenuButton];

    self.shuffleButton = [self makeIconButton:@"IcoShuffle" selectedImage:@"IcoShuffleBlue" action:@selector(shuffleTapped:)];
    [self.mainPane addSubview:self.shuffleButton];

    self.repeatButton = [self makeIconButton:@"IcoRepeat" selectedImage:@"IcoRepeatBlue" action:@selector(repeatTapped:)];
    [self.mainPane addSubview:self.repeatButton];

    // Sits under every transport key, so the glyphs stay crisp on top of it.
    self.transportBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.transportBar.backgroundColor = [UIColor whiteColor];
    // The pill and the glyphs sitting on it are one unit, so they change
    // together: a dark surface needs light glyphs, a light one needs dark ones.
    [LTTheme setTintColor:[LTTheme text] onView:self.transportBar];
    self.transportBar.userInteractionEnabled = NO; // taps go to the buttons
    self.transportBar.hidden = YES;
    [self.mainPane insertSubview:self.transportBar belowSubview:self.prevButton];

    // Halo for the held key. A soft accent tint rather than white, because the
    // row is already a white pill and a white glow on white would be invisible.
    self.pressGlow = [[UIView alloc] initWithFrame:CGRectZero];
    // A soft accent tint rather than white, because the row is already a pill
    // and a white glow on white would be invisible. The modern themes use the
    // accent colour; the native one keeps its blue.
    self.pressGlow.backgroundColor = [LTTheme isModern]
        ? [[LTTheme accent] colorWithAlphaComponent:0.30f]
        : [UIColor colorWithRed:0.42f green:0.62f blue:0.95f alpha:0.30f];
    self.pressGlow.userInteractionEnabled = NO;
    // Kept permanently in the hierarchy at alpha 0. Hiding/unhiding or moving it
    // during a touch cancels that touch on iOS 4, so only its alpha and frame
    // are ever changed from the button handlers.
    self.pressGlow.alpha = 0.0f;
    [self.mainPane insertSubview:self.pressGlow belowSubview:self.prevButton];

    // Black to match the transport glyphs: they sit on the same white pill, so a
    // white icon here would be invisible.
    // Matched to the transport glyphs: they sit on the same pill, so the icons
    // have to contrast with it. Light on the dark theme, dark on the light one.
    UIColor *glyphColor = [UIColor blackColor];
    if ([LTTheme isModern]) {
        glyphColor = [LTTheme isDark] ? [UIColor whiteColor] : [UIColor blackColor];
    }
    self.airPlayButton = [self makeUtilityButtonWithImage:[LTLucideIcons iconNamed:@"airplay" size:20.0f color:glyphColor]
                                                   action:@selector(airPlayTapped)];
    self.playlistButton = [self makeUtilityButtonWithImage:nil action:@selector(menuTapped)];
    [self.playlistButton setTitle:@"\u22EF" forState:UIControlStateNormal];
    self.playlistButton.titleLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    [self.playlistButton setTitleColor:glyphColor forState:UIControlStateNormal];
    [self.mainPane addSubview:self.airPlayButton];
    [self.mainPane addSubview:self.playlistButton];

    // Must run after every key exists: adding a target to a nil button is a
    // silent no-op, which is why the utility keys had no press feedback.
    for (UIButton *key in [NSArray arrayWithObjects:self.shuffleButton, self.prevButton,
                           self.playButton, self.nextButton, self.repeatButton,
                           self.airPlayButton, self.playlistButton, nil]) {
        [self addPressFeedbackToButton:key];
    }

    self.utilityBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.utilityBar.backgroundColor = [LTTheme isModern] ? [LTTheme cellBackground] : [UIColor whiteColor];
    self.utilityBar.userInteractionEnabled = NO;
    self.utilityBar.hidden = YES;
    [self.mainPane insertSubview:self.utilityBar belowSubview:self.airPlayButton];

    // MPVolumeView has no public "route button" accessor, so the documented
    // workaround is to keep the view in the hierarchy and send actions to the
    // UIButton inside it. Parked off-screen so it never draws.
    self.routeVolumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-2000.0f, -2000.0f, 1.0f, 1.0f)];
    [self.mainPane addSubview:self.routeVolumeView];

    self.pagesHint = [[UILabel alloc] init];
    self.pagesHint.text = @"Swipe down for queue   \u00B7   Swipe up for info";
    self.pagesHint.textAlignment = NSTextAlignmentCenter;
    self.pagesHint.font = [UIFont boldSystemFontOfSize:12];
    self.pagesHint.textColor = [UIColor colorWithWhite:0.85f alpha:0.85f];
    self.pagesHint.backgroundColor = [UIColor clearColor];
    self.pagesHint.hidden = YES;
    [self.mainPane addSubview:self.pagesHint];

    [self applyNowPlayingPolish];
    [self layoutControls];
    [self buildQueuePane];
    [self buildStatsPane];
    [self layoutPages];
    // -viewDidLayoutSubviews is iOS 5+. On iOS 4 it never runs, so the drawer's
    // table, segmented control and scroll views keep their CGRectZero frames
    // and the drawers appear empty. Lay them out here as well.
    [self layoutPageSubviews];
    [self setupSwipeGestures];
    [self applyTransportImages];
    self.lastGlyphMode = NSNotFound;
}

// Small visual refinements that make the screen feel less flat: an accent-tinted
// scrubber, legible text over any artwork, a hairline around the cover and a
// soft gradient instead of the old flat scrim.
- (void)applyNowPlayingPolish {
    // Scrubber: accent progress, a translucent white remainder and a white
    // thumb. UISlider tint properties arrived in iOS 5, so they are guarded.
    if ([self.progressSlider respondsToSelector:@selector(setMinimumTrackTintColor:)])
        [self.progressSlider setMinimumTrackTintColor:[LTTheme accent]];
    if ([self.progressSlider respondsToSelector:@selector(setMaximumTrackTintColor:)])
        [self.progressSlider setMaximumTrackTintColor:[[UIColor whiteColor] colorWithAlphaComponent:0.35f]];
    if ([self.progressSlider respondsToSelector:@selector(setThumbTintColor:)])
        [self.progressSlider setThumbTintColor:[UIColor whiteColor]];

    // A faint shadow keeps the white labels readable when the cover behind
    // them is light. UILabel has had these since iOS 3.2, guarded anyway.
    UIColor *shadow = [UIColor colorWithWhite:0.0f alpha:0.55f];
    for (UILabel *label in [NSArray arrayWithObjects:self.titleLabel, self.artistLabel,
                            self.sourceLabel, self.elapsedLabel, self.remainingLabel, nil]) {
        if ([label respondsToSelector:@selector(setShadowColor:)]) [label setShadowColor:shadow];
        if ([label respondsToSelector:@selector(setShadowOffset:)]) [label setShadowOffset:CGSizeMake(0.0f, 1.0f)];
    }
    // A subtle hairline gives the cover a defined edge over the backdrop.
    if (self.artworkView && [self.artworkView respondsToSelector:@selector(layer)]) {
        CALayer *layer = self.artworkView.layer;
        if ([layer respondsToSelector:@selector(setBorderWidth:)]) [layer setBorderWidth:1.0f];
        if ([layer respondsToSelector:@selector(setBorderColor:)])
            [layer setBorderColor:[[UIColor whiteColor] colorWithAlphaComponent:0.18f].CGColor];
    }

    // Replace the flat 30% black scrim with a gradient that deepens towards the
    // controls. CAGradientLayer is checked at runtime for the oldest devices.
    Class gradientClass = NSClassFromString(@"CAGradientLayer");
    if (gradientClass && self.scrimView && !self.gradientScrim) {
        CAGradientLayer *gradient = [gradientClass layer];
        gradient.frame = self.scrimView.bounds;
        gradient.colors = [NSArray arrayWithObjects:
                           (id)[[UIColor colorWithWhite:0.0f alpha:0.08f] CGColor],
                           (id)[[UIColor colorWithWhite:0.0f alpha:0.55f] CGColor], nil];
        gradient.locations = [NSArray arrayWithObjects:
                              [NSNumber numberWithFloat:0.0f],
                              [NSNumber numberWithFloat:1.0f], nil];
        [self.scrimView.layer insertSublayer:gradient atIndex:0];
        self.gradientScrim = gradient;
        self.scrimView.backgroundColor = [UIColor clearColor];
    }
}

- (void)setupSwipeGestures {
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.maximumNumberOfTouches = 1;
    pan.minimumNumberOfTouches = 1;
    pan.delegate = self;
    // A tap with a little finger jitter must not be stolen by the swipe: when a
    // pan recognizer begins it cancels the touches of the controls underneath
    // it, which made every transport key take two taps intermittently.
    pan.cancelsTouchesInView = NO;
    // delaysTouchesBegan is YES by default. On slow hardware UIKit holds the
    // button's TouchDown until the pan fails, so a quick tap can deliver
    // TouchUpInside without a matching down and the action never fires. Deliver
    // touches immediately; the delegate below rejects taps from starting pans.
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    self.swipePan = pan;
    [self.mainPane addGestureRecognizer:pan];

    // This pan opens BOTH drawers: keep it on every iOS version so the queue
    // drawer still works. The handler refuses only the bottom/info direction on
    // iOS 5 and earlier.
    self.mainVerticalPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mainVerticalPan:)];
    self.mainVerticalPan.delegate = self;
    self.mainVerticalPan.cancelsTouchesInView = NO;
    self.mainVerticalPan.delaysTouchesBegan = NO;
    self.mainVerticalPan.delaysTouchesEnded = NO;
    [self.mainPane addGestureRecognizer:self.mainVerticalPan];

    if (LTInfoDrawerAllowed()) {
        self.statsDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drawerDragged:)];
        self.statsDrag.delegate = self;
        // A pan defaults to cancelsTouchesInView = YES, which meant that as soon as the
        // drawer drag recognised it tore the touch out of the drawer's scroll views and
        // cancelled the page pan underneath. Without this the page swipe could be
        // recognised and then immediately killed by the drawer.
        self.statsDrag.cancelsTouchesInView = NO;
        self.statsDrag.delaysTouchesBegan = NO;
        self.statsDrag.delaysTouchesEnded = NO;
        [self.statsPane addGestureRecognizer:self.statsDrag];
    }

    self.queueDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drawerDragged:)];
    self.queueDrag.delegate = self;
    self.queueDrag.delaysTouchesBegan = NO;
    self.queueDrag.delaysTouchesEnded = NO;
    // On old iOS the delegate's touch filtering is unreliable, so a pan on the
    // whole pane made the area around the handle enormous. Attach it directly to
    // the compact handle instead; opening still works through mainVerticalPan.
    UIView *queueDragView = LTInfoDrawerAllowed() ? self.queuePane : self.queueHandle;
    [queueDragView addGestureRecognizer:self.queueDrag];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    BOOL dock = [self isDockMode];
    if ([self.infoPagePans containsObject:(id)gestureRecognizer]) {
        // Only claim the touch for paging when the movement is genuinely sideways,
        // so a vertical pull on the drawer is not stolen mid-gesture.
        CGPoint v = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.statsPane];
        if (fabs(v.x) <= fabs(v.y)) return NO;
        return fabs(v.x) > 120.0f;
    }
    if (gestureRecognizer == self.swipePan) {
        // In dock mode the horizontal axis belongs to the side drawers; the
        // artwork swipe (track-changing) switches off in favour of the buttons.
        if (dock) return NO;
        CGPoint v = [self.swipePan velocityInView:self.mainPane];
        // Require a deliberate horizontal flick; otherwise a tap with slight
        // jitter has vx > vy and the pan would begin and cancel the button tap.
        return fabs(v.x) > 120.0f && fabs(v.x) > fabs(v.y) * 1.5f;
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

// The drawer drag and the page pan must never both be live: one moves the pane,
// the other moves the pages, and running together is what made the drawer appear
// to slide around in every direction.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // The drawer drags must never overlap the page pan: one moves the pane, the
    // other moves the pages, and together they read as the drawer sliding freely.
    if (gestureRecognizer == self.statsDrag || gestureRecognizer == self.queueDrag) return NO;
    if (other == self.statsDrag || other == self.queueDrag) return NO;

    // The page pan and a scroll view's own pan DO need to run together. The page
    // pan takes horizontal drags, the scroll view keeps vertical ones, and neither
    // has to yield. contentSize.width always equals the page width, so the scroll
    // view has nothing to scroll horizontally even while both are tracking.
    BOOL pagePanInvolved = [self.infoPagePans containsObject:(id)gestureRecognizer] ||
                           [gestureRecognizer.view isKindOfClass:[UIScrollView class]];
    BOOL otherInvolved = [self.infoPagePans containsObject:(id)other] ||
                         [other.view isKindOfClass:[UIScrollView class]];
    if (pagePanInvolved && otherInvolved) return YES;

    return YES;
}

// Drawer drags must only start outside the scrollable middle region, so the
// queue table / lyrics scroll keep their normal scrolling. Touches on the handle
// strips and empty drawer margins move the drawer instead.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // Transport buttons and the scrubber must win their taps outright. The
    // swipe/drag pan lives on their superview, so without this a slightly
    // slanted tap could start a pan and swallow the control's touch.
    if (gestureRecognizer == self.swipePan || gestureRecognizer == self.mainVerticalPan) {
        UIView *v = [touch view];
        while (v && v != self.mainPane) {
            if ([v isKindOfClass:[UIControl class]]) return NO;
            v = [v superview];
        }
    }
    // A page swipe must not begin on the drawer handle, in either layout. In dock
    // mode the handle is the vertical strip on the drawer's inner edge; in the
    // stacked layout it is the bar across the top. Either way that area belongs to
    // the drawer drag alone.
    if ([self.infoPagePans containsObject:(id)gestureRecognizer] && self.statsHandle) {
        CGPoint p = [touch locationInView:self.statsHandle];
        return !CGRectContainsPoint(self.statsHandle.bounds, p);
    }
    if (gestureRecognizer == self.queueDrag && self.queueTable) {
        CGPoint p = [touch locationInView:self.queueTable];
        return !CGRectContainsPoint(self.queueTable.bounds, p);
    }
    if (gestureRecognizer == self.statsDrag) {
        if ([self isDockMode]) {
            // In dock mode the drawer slides sideways, which is the same axis the
            // page pan uses. Letting the whole drawer body start a drawer drag made
            // both gestures run at once -- the pane and the pages moved together and
            // it read as the drawer sliding around freely. So the handle strip owns
            // the drag outright and everything else belongs to paging.
            CGPoint p = [touch locationInView:self.statsHandle];
            return CGRectContainsPoint(self.statsHandle.bounds, p);
        }
        // Stacked layout: the drawer slides vertically, so only the top handle
        // strip drags it. Whichever info page is on top keeps its own scrolling.
        CGPoint p = [touch locationInView:self.statsHandle];
        return CGRectContainsPoint(self.statsHandle.bounds, p);
    }
    return YES;
}

// Make a page swipe beat the drawer drag, so a horizontal swipe inside the drawer
// changes page instead of sliding the drawer shut. Because touches starting on
// the handle never reach the swipe at all, this does not make the handle feel
// sluggish: there the drag is the only contender and runs immediately.
// The drawer drags wait for the page pan rather than the other way round.
//
// This is asked of gestureRecognizer as "must this fail before other recognises?",
// so returning YES for the drag recognisers is what gives the page pan priority.
// The previous version returned YES for the swipe, which asked the opposite
// question and handed the drag the win -- which is why paging never worked in dock
// mode, where the drag is horizontal and genuinely competes.
//
// Nothing is made sluggish by this: touches starting on the handle never reach
// the page pan at all, and a vertical drag fails the pan's horizontal test within a
// frame or two, releasing the drawer.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    if (![self.infoPagePans containsObject:(id)other]) return NO;
    return (gestureRecognizer == self.statsDrag) || (gestureRecognizer == self.queueDrag);
}

- (CGFloat)drawerHeight {
    CGFloat h = self.view.bounds.size.height;
    // On iOS 5 and earlier the bottom info drawer is gone, so this height only
    // drives the top queue drawer. A fixed fraction left dead table space around
    // the grip: a band above it when the queue was short, and a band below it
    // when the fraction shrank. Fit the panel to the actual queue instead, so
    // the grip lands just under the last row with no empty strip on either side.
    if (!LTInfoDrawerAllowed()) {
        NSInteger count = (NSInteger)[[LTPlayerController sharedController].queue count];
        CGFloat headerH = 36.0f;
        CGFloat rowH = 50.0f;
        CGFloat gripAllowance = 8.0f;
        CGFloat contentH = headerH + (CGFloat)count * rowH + gripAllowance;
        CGFloat maxH = floorf(h * 0.70f);
        if (contentH > maxH) contentH = maxH;
        if (contentH < 120.0f) contentH = 120.0f;
        return contentH;
    }
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
        [LTTransitionSettings animateWithDuration:0.25f
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
    // Final backstop: even a caller that bypasses the gestures cannot open the
    // info drawer on iOS 5 or earlier.
    if (!LTInfoDrawerAllowed()) open = NO;
    LTLog(@"DRAWER setOpen=%d dock=%d current=%d", open, [self isDockMode] ? 1 : 0, _statsDrawerOpen);
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
    if (index == 1 && !LTInfoDrawerAllowed()) return;
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
            } else if (self.statsDrawerOpen && LTInfoDrawerAllowed()) {
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
                NSInteger target = (t > 0.0f) ? 0 : 1;
                // On old iOS the bottom/info direction belongs to no drawer;
                // ignore it instead of starting a drag that cannot open.
                if (target == 1 && !LTInfoDrawerAllowed()) break;
                [self beginDrawerDragAtIndex:target];
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
                self.swipeTransitionInProgress = YES;
                CGFloat dirOff = (self.panSwipeDir > 0) ? 1.0f : -1.0f;
                CGFloat offX = self.panBaseX * dirOff + self.artworkView.bounds.size.width * dirOff;
                [LTTransitionSettings animateWithDuration:0.18f animations:^{
                    self.artworkView.center = CGPointMake(self.panBaseX + offX, self.artworkView.center.y);
                    self.artworkView.alpha = 0.0f;
                    self.artworkView.transform = CGAffineTransformMakeScale(0.9f, 0.9f);
                    self.incomingArtworkView.center = CGPointMake(self.panBaseX, self.artworkView.center.y);
                    self.incomingArtworkView.alpha = 1.0f;
                } completion:^(BOOL finished){
                    NSInteger dir = self.panSwipeDir;
                    UIImage *preview = self.incomingArtworkView.image;

                    // Claim the incoming track's identity BEFORE skipping. Any
                    // refresh the skip triggers then sees the cover as already
                    // current and swaps it in place, rather than replaying the
                    // slide the drag just played.
                    LTTrack *adjacent = [[LTPlayerController sharedController] peekTrackOffset:(dir > 0) ? -1 : 1];
                    if (adjacent) self.artworkVideoId = adjacent.videoId;

                    if (dir > 0) {
                        [[LTPlayerController sharedController] previousTrack];
                    } else {
                        [[LTPlayerController sharedController] nextTrack];
                    }
                    // refreshTrack ran synchronously inside the skip above and
                    // called resetArtworkPresentation. With the swipe flag still
                    // set, that call only reset bookkeeping and left the sliding
                    // views alone. Now restore the artwork to its resting position
                    // with the sliding-in preview (or the previous cover if the
                    // preview didn't load in time on a fast swipe), then clear the
                    // flag so later resets work normally.
                    if (preview) {
                        self.artworkView.image = preview;
                    } else if (self.outgoingArtworkImage) {
                        self.artworkView.image = self.outgoingArtworkImage;
                        self.outgoingArtworkImage = nil;
                    }
                    self.artworkView.center = self.artworkRestingCenter;
                    self.artworkView.transform = CGAffineTransformIdentity;
                    self.artworkView.alpha = 1.0f;
                    self.incomingArtworkView.image = nil;
                    self.incomingArtworkView.alpha = 0.0f;
                    self.incomingArtworkView.transform = CGAffineTransformIdentity;
                    self.incomingArtworkView.center = self.artworkRestingCenter;
                    self.spinner.center = self.artworkRestingCenter;
                    self.panBaseX = self.artworkRestingCenter.x;
                    self.panSwipeDir = 0;
                    self.swipeTransitionInProgress = NO;
                }];
            } else {
                self.swipeTransitionInProgress = NO;
                [LTTransitionSettings animateWithDuration:0.22f animations:^{
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
            self.swipeTransitionInProgress = NO;
            [LTTransitionSettings animateWithDuration:0.22f animations:^{
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
    __unsafe_unretained LTPlayerViewController *weakSelf = self;
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
    if (self.swipeTransitionInProgress) {
        self.panBaseX = self.artworkRestingCenter.x;
        self.spinner.center = self.artworkRestingCenter;
        self.panSwipeDir = 0;
        return;
    }
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

// Recolours a glyph image to a flat colour.
//
// The transport glyphs are bundled PNGs in one fixed colour, so the theme
// cannot tint them. Drawing the image as a mask over a filled rectangle
// replaces whatever colour it was with ours, keeping the shape.
static UIImage *LTTintedImage(UIImage *image, UIColor *color) {
    if (!image || !color) return image;
    CGImageRef cg = image.CGImage;
    if (!cg) return image;
    size_t width = CGImageGetWidth(cg);
    size_t height = CGImageGetHeight(cg);
    if (width == 0 || height == 0) return image;

    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        UIGraphicsEndImageContext();
        return image;
    }
    [color setFill];
    UIRectFill(CGRectMake(0.0f, 0.0f, image.size.width, image.size.height));
    // Keep the filled colour only where the glyph is opaque.
    CGContextSaveGState(ctx);
    CGContextSetBlendMode(ctx, kCGBlendModeDestinationIn);
    [image drawInRect:CGRectMake(0.0f, 0.0f, image.size.width, image.size.height)];
    CGContextRestoreGState(ctx);
    UIImage *tinted = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return tinted ?: image;
}

- (UIButton *)makeIconButton:(NSString *)imageName selectedImage:(NSString *)selectedImageName action:(SEL)action {
    UIButton *button = [LTTapResilientButton buttonWithType:UIButtonTypeCustom];
    UIImage *normal = [UIImage imageNamed:imageName];
    UIImage *selected = [UIImage imageNamed:selectedImageName];
    // These are placeholders until -applyTransportImages draws the real glyphs
    // at the size the layout needs.
    [button setImage:normal forState:UIControlStateNormal];
    [button setImage:selected forState:UIControlStateSelected];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

// Rings the enlarged transport controls so the floating glyphs read as buttons.
- (void)applyCircleToButton:(UIButton *)button diameter:(CGFloat)diameter {
    if (diameter <= 0.0f) return;
    button.layer.cornerRadius = diameter / 2.0f;
    button.layer.backgroundColor = [UIColor whiteColor].CGColor;
    // In the modern themes the main play key gets a thin accent ring, making
    // it the clear focal point of the row. The other discs stay plain.
    if (button == self.playButton && [LTTheme isModern]) {
        button.layer.borderWidth = 2.0f;
        button.layer.borderColor = [LTTheme accent].CGColor;
    } else {
        button.layer.borderWidth = 0.0f;
        button.layer.borderColor = NULL;
    }
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
    // The modern themes use a surface, the native one the white it always was.
    self.transportBar.backgroundColor = [LTTheme isModern] ? [LTTheme cellBackground] : [UIColor whiteColor];
    // A soft shadow lifts the pill off the artwork, and a faint accent hairline
    // ties it to the rest of the themed chrome.
    self.transportBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.transportBar.layer.shadowOpacity = 0.20f;
    self.transportBar.layer.shadowOffset = CGSizeMake(0.0f, 3.0f);
    self.transportBar.layer.shadowRadius = 8.0f;
    self.transportBar.layer.masksToBounds = NO;
    if ([LTTheme isModern]) {
        self.transportBar.layer.borderWidth = 1.0f;
        self.transportBar.layer.borderColor = [[LTTheme accent] colorWithAlphaComponent:0.35f].CGColor;
    } else {
        self.transportBar.layer.borderWidth = 0.0f;
        self.transportBar.layer.borderColor = NULL;
    }
    self.transportBar.hidden = NO;
}

// The iPad and notched-phone layouts keep their per-key discs.
- (void)useTransportCircles {
    if (self.transportBar) self.transportBar.hidden = YES;
    // The utility keys only exist in the pill layouts; the enlarged and iPad
    // rows have no room for them and keep their own arrangement.
    if (self.airPlayButton) self.airPlayButton.hidden = YES;
    if (self.playlistButton) self.playlistButton.hidden = YES;
    if (self.utilityBar) self.utilityBar.hidden = YES;
}

// Base key size for the pill row; the fit calculation shrinks it if seven
// controls will not fit the screen.
static const CGFloat transportRowButtonSize = 36.0f;

// A short motor pulse plus a soft halo while a transport key is held, so the
// press is confirmed under the thumb before anything actually happens.
// Lays a row of buttons out left to right. Shared by the legacy portrait row and
// the landscape dock so the spacing rules stay identical.
- (void)layoutRowOfButtons:(NSArray *)buttons startX:(CGFloat)startX y:(CGFloat)y
                      size:(CGFloat)size spacing:(CGFloat)spacing {
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIButton *button = [buttons objectAtIndex:i];
        button.frame = CGRectMake(startX + (size + spacing) * (CGFloat)i, y, size, size);
    }
}

// The five playback keys, shared by every row layout.
- (NSArray *)playbackRowButtons {
    return [NSArray arrayWithObjects:self.shuffleButton, self.prevButton, self.playButton,
            self.nextButton, self.repeatButton, nil];
}

// The full pill: AirPlay on the far left, add-to-playlist on the far right.
- (NSArray *)barRowButtons {
    return [NSArray arrayWithObjects:self.airPlayButton, self.shuffleButton, self.prevButton,
            self.playButton, self.nextButton, self.repeatButton, self.playlistButton, nil];
}

// Utility keys parked in the top-right corner, used by the landscape dock where
// the pill has no room for them.
- (void)layoutUtilityButtonsTopRight {
    CGFloat width = self.view.bounds.size.width;
    CGFloat size = 30.0f;
    // The pill keeps the same margin from the top and the right as the rest
    // of the screen's furniture.
    const CGFloat margin = 10.0f;
    // A small pill just behind the pair, matching the transport bar's treatment.
    const CGFloat pad = 5.0f;
    CGFloat y = LTSafeAreaTop(self.view) + margin;
    CGFloat right = width - margin - pad;
    CGFloat left = right - size * 2.0f - 4.0f;
    self.airPlayButton.frame = CGRectMake(left, y, size, size);
    self.playlistButton.frame = CGRectMake(right - size, y, size, size);

    CGFloat barW = size * 2.0f + 4.0f + pad * 2.0f;
    self.utilityBar.frame = CGRectMake(left - pad, y, barW, size);
    self.utilityBar.layer.cornerRadius = size / 2.0f;
    self.utilityBar.backgroundColor = [LTTheme isModern] ? [LTTheme cellBackground] : [UIColor whiteColor];
    self.utilityBar.hidden = NO;
}

// Picks a size and gap for `count` buttons that fit inside `available`, keeping
// the tap targets as large as the row allows.
- (BOOL)fitRowOfCount:(NSInteger)count available:(CGFloat)available
                 size:(CGFloat *)outSize spacing:(CGFloat *)outSpacing {
    CGFloat size = MIN(transportRowButtonSize, available / (CGFloat)count);
    CGFloat spacing = (available - size * (CGFloat)count) / (CGFloat)(count - 1);
    // Below ~4pt the pill starts reading as a solid block, so shrink the buttons
    // instead of collapsing the gaps.
    if (spacing < 4.0f) {
        spacing = 4.0f;
        size = (available - spacing * (CGFloat)(count - 1)) / (CGFloat)count;
    }
    if (size < 24.0f) return NO;
    if (outSize) *outSize = size;
    if (outSpacing) *outSpacing = spacing;
    return YES;
}

- (void)addPressFeedbackToButton:(UIButton *)button {
    [button addTarget:self action:@selector(transportKeyDown:)
     forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(transportTouchUpInside:)
     forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(transportTouchUpOutside:)
     forControlEvents:UIControlEventTouchUpOutside];
    [button addTarget:self action:@selector(transportTouchCancelled:)
     forControlEvents:UIControlEventTouchCancel];
}

- (UIButton *)makeUtilityButtonWithImage:(UIImage *)image action:(SEL)action {
    UIButton *button = [LTTapResilientButton buttonWithType:UIButtonTypeCustom];
    [button setImage:image forState:UIControlStateNormal];
    button.contentMode = UIViewContentModeCenter;
    button.backgroundColor = [UIColor clearColor];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    button.userInteractionEnabled = YES;
    return button;
}

- (void)menuTapped {
    if (self.pressGlow) self.pressGlow.alpha = 0.0f;
    [self dismissCustomMenu];
    LTPlayerController *pc = [LTPlayerController sharedController];
    LTTrack *cur = [pc currentTrack];
    NSMutableArray *items = [NSMutableArray arrayWithObjects:@"Add to Playlist", @"Add to Library", nil];
    NSString *downloadLabel = ([[LTPlaylistStore sharedStore] isTrackDownloaded:cur]) ? @"Remove Download" : @"Add to Download Queue";
    [items addObject:downloadLabel];
    if ([pc radioEnabled]) {
        [items addObject:@"Recommend more songs like this"];
        [items addObject:@"Don't recommend songs like this"];
        [items addObject:@"Block song from station"];
    }

    CGRect bounds = self.view.bounds;
    CGFloat screenH = bounds.size.height;
    CGFloat panelWidth = MIN(340.0f, bounds.size.width - 24.0f);
    CGFloat rowHeight = 52.0f;
    CGFloat panelHeight = rowHeight * (items.count + 1) + 16.0f;

    CGFloat bottomInset = 0;
    @try {
        bottomInset = LTSafeAreaInsets(self.view).bottom;
    } @catch (NSException *e) { bottomInset = 0; }

    self.customMenuBackdrop = [[UIView alloc] initWithFrame:bounds];
    self.customMenuBackdrop.backgroundColor = [UIColor colorWithWhite:0.0f alpha:[LTTheme isDark] ? 0.6f : 0.45f];
    self.customMenuBackdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(customMenuBackdropTapped:)];
    [self.customMenuBackdrop addGestureRecognizer:tap];
#if !__has_feature(objc_arc)
    [tap release];
#endif
    [self.view addSubview:self.customMenuBackdrop];

    self.customMenuContainer = [[UIView alloc] initWithFrame:CGRectMake((bounds.size.width - panelWidth) / 2.0f,
                                                                         screenH - panelHeight - 12.0f - bottomInset,
                                                                         panelWidth, panelHeight)];
    self.customMenuContainer.backgroundColor = [LTTheme cellBackground];
    self.customMenuContainer.layer.cornerRadius = [LTTheme isModern] ? 24.0f : [LTTheme largeCornerRadius];
    self.customMenuContainer.clipsToBounds = YES;
    self.customMenuContainer.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                                UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.customMenuContainer];

    CGFloat y = 8.0f;
    for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
        NSString *title = [items objectAtIndex:(NSUInteger)i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(0, y, panelWidth, rowHeight);
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
        btn.titleLabel.font = [UIFont systemFontOfSize:16];
        [btn setTitle:title forState:UIControlStateNormal];
        [btn setTitleColor:[LTTheme text] forState:UIControlStateNormal];
        btn.tag = i;
        [btn addTarget:self action:@selector(customMenuItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.customMenuContainer addSubview:btn];
        y += rowHeight;
        if (i < (NSInteger)items.count - 1) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(16, y - 0.5f, panelWidth - 32, 1.0f)];
            sep.backgroundColor = [LTTheme separator];
            [self.customMenuContainer addSubview:sep];
        }
    }

    // Cancel button
    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
    cancel.frame = CGRectMake(0, y, panelWidth, rowHeight);
    cancel.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancel setTitleColor:[LTTheme accent] forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(dismissCustomMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.customMenuContainer addSubview:cancel];

    self.customMenuContainer.alpha = 0.0f;
    self.customMenuContainer.transform = CGAffineTransformMakeScale(0.95f, 0.95f);
    [LTTransitionSettings animateWithDuration:0.18f animations:^{
        self.customMenuContainer.alpha = 1.0f;
        self.customMenuContainer.transform = CGAffineTransformIdentity;
        self.customMenuBackdrop.alpha = 1.0f;
    }];
}

- (void)customMenuBackdropTapped:(UITapGestureRecognizer *)g {
    [self dismissCustomMenu];
}

- (void)dismissCustomMenu {
    if (!self.customMenuContainer) return;
    [LTTransitionSettings animateWithDuration:0.15f animations:^{
        self.customMenuContainer.alpha = 0.0f;
        self.customMenuContainer.transform = CGAffineTransformMakeScale(0.95f, 0.95f);
        self.customMenuBackdrop.alpha = 0.0f;
    } completion:^(BOOL finished) {
        [self.customMenuContainer removeFromSuperview];
        [self.customMenuBackdrop removeFromSuperview];
        self.customMenuContainer = nil;
        self.customMenuBackdrop = nil;
    }];
}

- (void)customMenuItemTapped:(UIButton *)sender {
    NSInteger index = sender.tag;
    LTPlayerController *pc = [LTPlayerController sharedController];
    LTTrack *current = [pc currentTrack];
    // Build item list to map index (no Cancel; cancel is a separate button)
    NSMutableArray *items = [NSMutableArray arrayWithObjects:@"Add to Playlist", @"Add to Library", nil];
    NSString *downloadLabel2 = ([[LTPlaylistStore sharedStore] isTrackDownloaded:current]) ? @"Remove Download" : @"Add to Download Queue";
    [items addObject:downloadLabel2];
    if ([pc radioEnabled]) {
        [items addObject:@"Recommend more songs like this"];
        [items addObject:@"Don't recommend songs like this"];
        [items addObject:@"Block song from station"];
    }
    NSString *title = (index >= 0 && index < (NSInteger)items.count) ? [items objectAtIndex:(NSUInteger)index] : nil;
    [self dismissCustomMenu];
    if (!title || [title isEqualToString:@"Cancel"]) return;
    if ([title isEqualToString:@"Add to Playlist"]) {
        [self addToPlaylistTapped];
        return;
    }
    if ([title isEqualToString:@"Add to Library"]) {
        LTTrack *tr = [[LTPlayerController sharedController] currentTrack];
        if (tr) {
            [[LTPlaylistStore sharedStore] addTrackToLibrary:tr];
            [self showToast:@"Added to library"];
        }
        return;
    }
    if ([title isEqualToString:@"Add to Download Queue"] || [title isEqualToString:@"Remove Download"]) {
        LTTrack *tr = [[LTPlayerController sharedController] currentTrack];
        if (tr) {
            if ([[LTPlaylistStore sharedStore] isTrackDownloaded:tr]) {
                [[LTPlaylistStore sharedStore] removeDownloadsForTracks:@[tr]];
                [self showToast:@"Removed download"];
            } else {
                [[LTPlaylistStore sharedStore] enqueueDownloads:@[tr]];
                [self showToast:@"Added to download queue"];
            }
        }
        return;
    }
    if ([title isEqualToString:@"Recommend more songs like this"]) {
        if (current) {
            [pc addLikedVideoIdForCurrentStation:current.videoId];
            [[LTYouTubeClient sharedClient] fetchRadioForTrack:current completion:^(NSArray *tracks, NSError *error) {
                if (tracks.count) {
                    NSMutableArray *toAdd = [NSMutableArray array];
                    for (LTTrack *t in tracks) {
                        if ([pc isStationBlacklistedVideoId:t.videoId]) continue;
                        BOOL exists = NO;
                        for (LTTrack *q in pc.queue) {
                            if ([q.videoId isEqualToString:t.videoId]) { exists = YES; break; }
                        }
                        if (!exists) [toAdd addObject:t];
                    }
                    if (toAdd.count) [pc enqueueTracks:toAdd];
                }
            }];
        }
        return;
    }
    if ([title isEqualToString:@"Don't recommend songs like this"]) {
        if (current) [pc blacklistVideoIdForCurrentStation:current.videoId];
        [pc nextTrack];
        return;
    }
    if ([title isEqualToString:@"Block song from station"]) {
        if (current) [pc blacklistVideoIdForCurrentStation:current.videoId];
        NSInteger i = pc.currentIndex;
        if (i >= 0 && i < (NSInteger)pc.queue.count) {
            [pc removeTrackAtIndex:i];
        }
        return;
    }
}

- (void)airPlayTapped {
    // Forward the tap to the route button MPVolumeView keeps inside itself.
    for (UIView *view in self.routeVolumeView.subviews) {
        if ([view isKindOfClass:[UIButton class]]) {
            [(UIButton *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
            return;
        }
    }
    LTLog(@"PLAYER airplay tapped but no route button found");
}

// Restored: this used to live in a section that was removed along with the
// visualizer, but the utility buttons need to confirm an action.
- (void)showToast:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 220, 36)];
    label.center = CGPointMake(self.view.bounds.size.width / 2.0f, self.view.bounds.size.height - 80.0f);
    label.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.75f];
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:13];
    label.layer.cornerRadius = 6.0f;
    label.clipsToBounds = YES;
    label.text = text;
    [self.view addSubview:label];
    [LTTransitionSettings animateWithDuration:1.4f delay:1.0f options:UIViewAnimationOptionCurveEaseIn
                     animations:^{ label.alpha = 0.0f; }
                     completion:^(BOOL finished) { [label removeFromSuperview]; }];
}

- (void)addToPlaylistTapped {
    LTTrack *track = [[LTPlayerController sharedController] currentTrack];
    if (!track) return;
    __unsafe_unretained LTPlayerViewController *weakSelf = self;
    [LTPlaylistPicker presentFromViewController:self
                                   panelTitle:track.title
                                    onPicked:^(LTLocalPlaylist *playlist) {
        [LTPlaylistStore addTrack:track
                       toPlaylist:playlist
                    confirmingFrom:weakSelf
                       completion:^(BOOL added) {
            if (added) [weakSelf showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
        }];
    } onCreateNew:^(NSString *name) {
        LTLocalPlaylist *playlist = [[LTPlaylistStore sharedStore] createPlaylistWithName:name];
        // A playlist that was just created is empty, so nothing can duplicate.
        if (playlist) {
            [LTPlaylistStore addTrack:track toPlaylist:playlist confirmingFrom:nil completion:nil];
            [weakSelf showToast:[NSString stringWithFormat:@"Added to %@", playlist.name]];
        }
    }];
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
    // The halo is permanent in the hierarchy (alpha 0 when idle) and only its
    // frame/opacity change here. On iOS 4 both un-hiding a sibling and starting
    // a UIView animation during TouchDown can cancel the touch, so neither is
    // done in the touch path. The resilient button subclass recovers touches
    // that UIKit still cancels on a very fast tap.
    self.pressGlow.alpha = 1.0f;
}

- (void)transportTouchUpInside:(UIButton *)button {
    [self transportKeyUp:button];
}

- (void)transportTouchUpOutside:(UIButton *)button {
    [self transportKeyUp:button];
}

- (void)transportTouchCancelled:(UIButton *)button {
    [self transportKeyUp:button];
}

- (void)transportKeyUp:(UIButton *)button {
    if (!self.pressGlow) return;
    self.pressGlow.alpha = 0.0f;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.backgroundImageView) self.backgroundImageView.frame = self.view.bounds;
    if (self.scrimView) self.scrimView.frame = self.view.bounds;
    if (self.gradientScrim) self.gradientScrim.frame = self.scrimView.bounds;
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
        self.stationMenuButton.frame = CGRectMake((width - sideSize) / 2.0f, areaTop + cornerInset - sideSize / 2.0f, sideSize, sideSize);

        [self applyCircleToButton:self.playButton diameter:playSize];
        [self applyCircleToButton:self.prevButton diameter:midSize];
        [self applyCircleToButton:self.nextButton diameter:midSize];
        [self applyCircleToButton:self.shuffleButton diameter:sideSize];
        [self applyCircleToButton:self.repeatButton diameter:sideSize];
        [self useTransportCircles];
    } else {
        // Shuffle and loop get the same size as the transport keys, so all five
        // glyphs line up on the one white pill below them.
        NSArray *row = [self barRowButtons];
        // The pill is lined up with the progress slider, which sits at a 16pt
        // margin on each side.
        CGFloat barWidth = width - 32.0f;
        CGFloat barX = 16.0f;
        const CGFloat barPad = 10.0f;
        CGFloat buttonSize = 0.0f, spacing = 0.0f;
        BOOL fits = [self fitRowOfCount:(NSInteger)row.count available:barWidth - barPad * 2.0f
                                    size:&buttonSize spacing:&spacing];
        CGFloat rowY = transportY + (transportH - buttonSize) / 2.0f;
        if (fits) {
            CGFloat rowWidth = buttonSize * (CGFloat)row.count + spacing * (CGFloat)(row.count - 1);
            CGFloat start = barX + (barWidth - rowWidth) / 2.0f;
            [self layoutRowOfButtons:row startX:start y:rowY size:buttonSize spacing:spacing];
            // Only the portrait pill carries the utility keys; landscape parks
            // them in the top-right corner instead.
            self.airPlayButton.hidden = NO;
            self.playlistButton.hidden = NO;
            self.utilityBar.hidden = YES; // the main pill covers them here
            [self useTransportBarInRect:CGRectMake(barX, rowY, barWidth, buttonSize)];
        } else {
            // Cannot fit seven controls: fall back to the playback keys alone.
            self.airPlayButton.hidden = YES;
            self.playlistButton.hidden = YES;
            NSArray *keys = [row subarrayWithRange:NSMakeRange(0, 5)];
            CGFloat keyAvailable = width - 16.0f;
            if ([self fitRowOfCount:5 available:keyAvailable size:&buttonSize spacing:&spacing]) {
                CGFloat rowWidth = buttonSize * 5.0f + spacing * 4.0f;
                [self layoutRowOfButtons:keys startX:(width - rowWidth) / 2.0f y:rowY
                                    size:buttonSize spacing:spacing];
                [self useTransportBarInRect:CGRectMake((width - rowWidth - 10.0f) / 2.0f, rowY,
                                                       rowWidth + 10.0f, buttonSize)];
            }
        }
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
    self.stationMenuButton.frame = CGRectMake(C - smallSize / 2.0f, smallY - smallSize - 8.0f, smallSize, smallSize);

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
    // Landscape has no room for seven controls, so the pill keeps the five
    // playback keys and the utility buttons move to the top-right corner.
    self.airPlayButton.hidden = NO;
    self.playlistButton.hidden = NO;
    [self layoutUtilityButtonsTopRight];
    NSArray *row = [self playbackRowButtons];
    const CGFloat barPad = 10.0f;
    CGFloat buttonSize = 0.0f, spacing = 0.0f;
    if ([self fitRowOfCount:(NSInteger)row.count available:ctrlW - barPad * 2.0f
                       size:&buttonSize spacing:&spacing]) {
        CGFloat rowWidth = buttonSize * 5.0f + spacing * 4.0f;
        CGFloat rowY = transportY + (transportH - buttonSize) / 2.0f;
        [self layoutRowOfButtons:row startX:ctrlX + (ctrlW - rowWidth) / 2.0f y:rowY
                            size:buttonSize spacing:spacing];
        [self useTransportBarInRect:CGRectMake(ctrlX, rowY, ctrlW, buttonSize)];
    }
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
    [self updateDrawerGloss];
}

- (UIView *)makeHandleView {
    UIView *strip = [[UIView alloc] initWithFrame:CGRectZero];
    strip.backgroundColor = [UIColor clearColor];
    strip.userInteractionEnabled = YES;

    UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 5)];
    grip.tag = 99;
    grip.backgroundColor = [LTTheme isModern]
        ? [[LTTheme accent] colorWithAlphaComponent:0.80f]
        : [UIColor colorWithWhite:1.0f alpha:0.55f];
    grip.layer.cornerRadius = 2.5f;
    [strip addSubview:grip];
    return strip;
}

- (void)centerGripInHandle:(UIView *)handle {
    UIView *grip = [handle viewWithTag:99];
    if (!grip) return;
    // On old iOS the handle is deliberately a large transparent hit area, so
    // centre a much smaller visible bar and park it at the bottom edge instead
    // of floating in the middle of the empty strip.
    if (!LTInfoDrawerAllowed() && handle == self.queueHandle) {
        CGFloat gw = 28.0f, gh = 4.0f;
        // Park the bar flush against the very bottom edge of the pane. Any inset
        // here shows up as a blank band between the grip and the drawer's edge.
        grip.frame = CGRectMake((handle.bounds.size.width - gw) / 2.0f,
                                handle.bounds.size.height - gh, gw, gh);
        grip.layer.cornerRadius = gh / 2.0f;
        return;
    }
    grip.frame = CGRectMake((handle.bounds.size.width - 40) / 2.0f,
                            (handle.bounds.size.height - 5) / 2.0f, 40, 5);
    grip.layer.cornerRadius = 2.5f;
}

- (void)buildQueuePane {
    self.queueHeader = [[UILabel alloc] initWithFrame:CGRectZero];
    self.queueHeader.font = [UIFont boldSystemFontOfSize:14];
    self.queueHeader.textColor = [LTTheme isModern] ? [LTTheme accent] : [self drawerTextColor];
    self.queueHeader.backgroundColor = [UIColor clearColor];
    [self.queuePane addSubview:self.queueHeader];

    self.queueTable = [[LTThemedTableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.queueTable.dataSource = self;
    self.queueTable.delegate = self;
    // The rows keep clear of the editing controls, the same as the queue
    // screen's.
    self.queueTable.leadingRowInset = 38.0f;
    self.queueTable.backgroundColor = [UIColor clearColor];
    self.queueTable.separatorColor = [LTTheme isModern]
        ? [LTTheme separator]
        : [UIColor colorWithWhite:1.0f alpha:0.25f];
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

// The name of the layer that carries a drawer's gloss, so it can be found
// again when the theme changes underneath it.
static NSString * const kLTDrawerGlossName = @"LTDrawerGloss";

// The text colour for the drawers.
//
// The drawers are a panel that follows the theme, so the text on them has to
// follow it too: white on the dark panel of the native theme, the theme's own
// colours when the modern themes are on.
- (UIColor *)drawerTextColor {
    if ([LTTheme isModern]) return [LTTheme text];
    return [UIColor whiteColor];
}

// The colour of a caption in a drawer.
- (UIColor *)drawerSecondaryTextColor {
    if ([LTTheme isModern]) return [LTTheme secondaryText];
    return [UIColor colorWithWhite:0.85f alpha:1.0f];
}

// The colour of the faintest text in a drawer.
- (UIColor *)drawerFaintTextColor {
    if ([LTTheme isModern]) return [LTTheme secondaryText];
    return [UIColor colorWithWhite:0.60f alpha:1.0f];
}

// The colour of the track that is playing, in the queue.
- (UIColor *)drawerHighlightColor {
    if ([LTTheme isModern]) return [LTTheme accent];
    return [UIColor colorWithRed:0.35f green:0.68f blue:1.0f alpha:1.0f];
}

// The panel a drawer is drawn on.
//
// The modern themes use their own surface, so a drawer looks like part of
// the app rather than a black overlay laid over it. iOS 6 gets the glossy
// panel of the time - a gradient with a highlight across the top - and
// everywhere else it is the dark overlay it has always been.
- (void)applyDrawerBackgroundTo:(UIView *)pane {
    for (CALayer *layer in [pane.layer.sublayers copy]) {
        if ([layer.name isEqualToString:kLTDrawerGlossName]) [layer removeFromSuperlayer];
    }
    if ([LTTheme isModern]) {
        pane.backgroundColor = [LTTheme background];
        return;
    }
    if ([LTTheme usesSkeuomorphicSurfaces]) {
        pane.backgroundColor = [UIColor clearColor];
        [self addGlossToDrawer:pane];
        return;
    }
    pane.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.97f];
}

// The glossy panel of the old iOS.
//
// The gradient underneath is semi-transparent, so the player shows through it,
// and the shine on top is the gloss texture: a band of light across the top
// and a fainter one along the bottom, the way a polished surface catches the
// light.
- (void)addGlossToDrawer:(UIView *)pane {
    CAGradientLayer *panel = [CAGradientLayer layer];
    panel.name = kLTDrawerGlossName;
    panel.colors = @[
        (id)[UIColor colorWithRed:0.243f green:0.267f blue:0.302f alpha:0.86f].CGColor,
        (id)[UIColor colorWithRed:0.043f green:0.051f blue:0.063f alpha:0.96f].CGColor,
    ];
    panel.startPoint = CGPointMake(0.5f, 0.0f);
    panel.endPoint = CGPointMake(0.5f, 1.0f);
    [pane.layer addSublayer:panel];

    // The gloss itself.
    UIImage *glossImage = [UIImage imageNamed:@"Gloss"];
    if (glossImage) {
        CALayer *gloss = [CALayer layer];
        gloss.contents = (id)glossImage.CGImage;
        gloss.contentsGravity = kCAGravityResize;
        gloss.contentsScale = [UIScreen mainScreen].scale;
        gloss.opacity = 0.15f;
        [panel addSublayer:gloss];
    }

    [self updateDrawerGloss];
}

// The gloss has to follow the drawer it is on.
- (void)updateDrawerGloss {
    for (UIView *pane in @[self.queuePane, self.statsPane]) {
        if (!pane) continue;
        for (CALayer *layer in pane.layer.sublayers) {
            if (![layer.name isEqualToString:kLTDrawerGlossName]) continue;
            layer.frame = pane.bounds;
            for (CALayer *gloss in layer.sublayers) {
                gloss.frame = layer.bounds;
            }
        }
    }
}

- (void)buildStatsPane {
    // Lyrics, General and the original video.
    self.infoPageControl = [[LTCompactSegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Lyrics", @"General", nil]];
    self.infoPageControl.selectedSegmentIndex = 0;
    // Keep this one compact on iOS 4 as well; it lives in a 26pt strip, where
    // the old Plain style's large text would spill out of the segment.
    [LTTheme setCompactStyleForSegmentedControl:self.infoPageControl];
    if ([self.infoPageControl respondsToSelector:@selector(setTitleTextAttributes:forState:)]) {
        if ([LTTheme usesSkeuomorphicSurfaces]) {
            // The system's own segmented control was the glossy one: a blue
            // gradient under the unselected segment and a silver one under the
            // selected, with the text the other way round. Leaving it to draw
            // itself is what makes it look right, so its background is not
            // cleared and the title colours are the classic pairing.
            NSMutableDictionary *normal = [NSMutableDictionary dictionary];
            [normal setObject:[UIFont boldSystemFontOfSize:13] forKey:NSFontAttributeName];
            [normal setObject:[UIColor whiteColor] forKey:NSForegroundColorAttributeName];
            [self.infoPageControl setTitleTextAttributes:normal forState:UIControlStateNormal];
            NSMutableDictionary *selected = [NSMutableDictionary dictionary];
            [selected setObject:[UIColor colorWithRed:0.11f green:0.24f blue:0.45f alpha:1.0f] forKey:NSForegroundColorAttributeName];
            [self.infoPageControl setTitleTextAttributes:selected forState:UIControlStateSelected];
        } else {
            self.infoPageControl.backgroundColor = [UIColor clearColor];
            NSMutableDictionary *normal = [NSMutableDictionary dictionary];
            [normal setObject:[UIFont boldSystemFontOfSize:13] forKey:NSFontAttributeName];
            [normal setObject:([LTTheme isModern] ? [LTTheme secondaryText] : [UIColor colorWithWhite:0.55f alpha:1.0f]) forKey:NSForegroundColorAttributeName];
            [self.infoPageControl setTitleTextAttributes:normal forState:UIControlStateNormal];
            NSMutableDictionary *selected = [NSMutableDictionary dictionary];
            [selected setObject:[UIColor colorWithWhite:0.95f alpha:1.0f] forKey:NSForegroundColorAttributeName];
            [self.infoPageControl setTitleTextAttributes:selected forState:UIControlStateSelected];
        }
    } else {
        if (![LTTheme usesSkeuomorphicSurfaces]) {
            self.infoPageControl.backgroundColor = [UIColor clearColor];
        }
        // iOS 4 has no title-attribute API; set the label fonts directly so the
        // captions stay inside the short segment.
        [LTTheme setTitleFont:[UIFont boldSystemFontOfSize:11] forSegmentedControl:self.infoPageControl];
    }
    if ([LTTheme isModern]) {
        [LTTheme setTintColor:[LTTheme accent] onView:self.infoPageControl];
    }
    [self.infoPageControl addTarget:self action:@selector(infoPageChanged:) forControlEvents:UIControlEventValueChanged];
    [self.statsPane addSubview:self.infoPageControl];

    self.lyricsScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.lyricsScroll.backgroundColor = [UIColor clearColor];
    self.lyricsScroll.alwaysBounceVertical = YES;
    self.lyricsScroll.clipsToBounds = YES;
    self.lyricsScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.lyricsScroll.directionalLockEnabled = YES;
    self.lyricsScroll.showsHorizontalScrollIndicator = NO;
    [self.statsPane addSubview:self.lyricsScroll];

    self.generalScroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.generalScroll.backgroundColor = [UIColor clearColor];
    self.generalScroll.alwaysBounceVertical = YES;
    self.generalScroll.clipsToBounds = YES;
    self.generalScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.generalScroll.directionalLockEnabled = YES;
    self.generalScroll.showsHorizontalScrollIndicator = NO;
    self.generalScroll.hidden = YES;
    [self.statsPane addSubview:self.generalScroll];


    // A horizontal pan drives the page change, so the pages slide with the finger
    // and settle based on distance or flick speed when it lifts.
    //
    // In dock mode the drawer itself is dragged sideways, so the two compete. The
    // split is by where the touch starts, not by disabling paging: the delegate
    // refuses the page pan for touches inside the drawer handle, so the handle
    // stays purely for dragging, and makes the drawer drag wait for the page pan
    // everywhere else. See -gestureRecognizer:shouldReceiveTouch: and
    // -gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:.
    // The page pans live on the page scroll views only -- deliberately NOT on the
    // drawer pane.
    //
    // A pan attached to the pane spans the entire drawer, including the band where
    // the segmented control sits, and it competes with the control's own touch
    // tracking. That left the Lyrics / General bar completely dead: taps
    // never reached it, so no page could be selected at all. Keeping the recognisers
    // strictly inside the page area means the control keeps the whole strip above it
    // to itself.
    self.infoPagePans = [NSMutableSet set];
    for (UIScrollView *scroll in @[self.lyricsScroll, self.generalScroll]) {
        if (!scroll) continue;
        UIPanGestureRecognizer *pagePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(infoPagePanned:)];
        pagePan.delegate = self;
        pagePan.cancelsTouchesInView = NO;
        pagePan.delaysTouchesBegan = NO;
        pagePan.delaysTouchesEnded = NO;
        [self.infoPagePans addObject:pagePan];
        [scroll addGestureRecognizer:pagePan];
    }
    self.infoPagePan = nil;

    self.statsHandle = [self makeHandleView];
    if (LTInfoDrawerAllowed()) {
        [self.statsHandle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(statsHandleTapped:)]];
        [self.statsPane addSubview:self.statsHandle];
    } else {
        // No drawer to close on old iOS, so do not show a handle for it either.
        self.statsHandle.hidden = YES;
    }
}

// Keeps a page no wider than the drawer it is in.
//
// The pages are slid by moving their frames, so a page must never scroll
// sideways. Its content size keeps the width it had when the lyrics were
// loaded - the portrait one - which is wider than the drawer in landscape, and
// a scroll view that wide can be scrolled sideways.
- (void)clampPageWidths {
    for (UIScrollView *page in @[self.lyricsScroll, self.generalScroll]) {
        if (!page) continue;
        CGFloat width = CGRectGetWidth(page.bounds);
        if (width < 1.0f) continue;
        if (page.contentSize.width > width) {
            page.contentSize = CGSizeMake(width, page.contentSize.height);
        }
    }
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
        [self clampPageWidths];
        [self relayoutLyrics];

        // Vertical handle strips on the edges facing the main content: queue's
        // on its right edge, lyrics' on its left.
        self.queueHandle.frame = LTInfoDrawerAllowed()
            ? CGRectMake(dw - strip, 0, strip, h)
            : CGRectMake(dw - 44.0f, (h - 140.0f) / 2.0f, 44.0f, 140.0f);
        self.queueHeader.frame = CGRectMake(16, 10 + topPad, dw - strip - 16, 22);
        self.queueTable.frame = CGRectMake(0, 36 + topPad, dw - strip, h - 36 - topPad);

        self.statsHandle.frame = CGRectMake(0, 0, strip, h);
        self.infoPageControl.frame = CGRectMake(16, 8 + topPad, dw - strip - 32, 26);
        self.lyricsScroll.frame = CGRectMake(16, 36 + topPad, dw - strip - 32, h - 36 - topPad);
        self.generalScroll.frame = self.lyricsScroll.frame;
        if (!self.infoPageSettling && ![self anyInfoPagePanActive]) {
            self.infoPageBaseFrame = self.lyricsScroll.frame;
            self.infoPageDragFrom = self.infoPageCurrent;
            self.infoPageNeighbor = self.infoPageDragFrom;
            [self resetInfoPageFramesKeepingPage:self.infoPageCurrent];
        }

            [self layoutDockHandleGrip:self.queueHandle];
        [self layoutDockHandleGrip:self.statsHandle];
        return;
    }

    CGFloat drawerH = [self drawerHeight];
    CGFloat handleH = 40.0f;
    // On old iOS the queue table runs right down to the pane edge so it meets
    // the bottom-flush grip with no blank band between them.
    CGFloat tablePad = LTInfoDrawerAllowed() ? handleH : 0.0f;
    CGFloat topPad = [self drawerTopPadding];
    [self clampPageWidths];
    [self relayoutLyrics];

    self.queueHandle.frame = LTInfoDrawerAllowed()
        ? CGRectMake(0, drawerH - handleH, w, handleH)
        : CGRectMake(0, drawerH - 50.0f, w, 50.0f);
    self.queueHeader.frame = CGRectMake(16, 10 + topPad, w - 32, 22);
    self.queueTable.frame = CGRectMake(0, 36 + topPad, w, drawerH - 36 - topPad - tablePad);

    self.statsHandle.frame = CGRectMake(0, 0, w, handleH);
    self.infoPageControl.frame = CGRectMake(16, handleH + 2, w - 32, 26);
    self.lyricsScroll.frame = CGRectMake(16, handleH + 32, w - 32, drawerH - handleH - 40);
    self.generalScroll.frame = self.lyricsScroll.frame;
    // The page pan slides frames relative to this, so a layout during a drag would
    // otherwise be fought by the pan and leave pages stranded off screen.
    if (!self.infoPageSettling && ![self anyInfoPagePanActive]) {
        self.infoPageBaseFrame = self.lyricsScroll.frame;
        self.infoPageDragFrom = self.infoPageCurrent;
        self.infoPageNeighbor = self.infoPageDragFrom;
        [self resetInfoPageFramesKeepingPage:self.infoPageCurrent];
    }

    [self centerGripInHandle:self.queueHandle];
    [self centerGripInHandle:self.statsHandle];

    LTLog(@"DRAWER layout pages L=%.0fx%.0f/h%d G=%.0fx%.0f/h%d C=%.0fx%.0f/h%d seg=%.0fx%.0f@%.0f",
          (double)self.lyricsScroll.bounds.size.width, (double)self.lyricsScroll.bounds.size.height, self.lyricsScroll.hidden,
          (double)self.generalScroll.bounds.size.width, (double)self.generalScroll.bounds.size.height, self.generalScroll.hidden,
          (double)0, (double)0, 1,
          (double)self.infoPageControl.bounds.size.width, (double)self.infoPageControl.bounds.size.height,
          (double)self.infoPageControl.frame.origin.y);

    // Flush any rows that arrived before the drawer had a usable width.
    if (self.generalPending && self.generalScroll.bounds.size.width >= 1.0f) {
        NSDictionary *pending = self.generalPending;
        self.generalPending = nil;
        [self renderGeneralInfo:pending];
    }
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
    [self applyNowPlayingPolish];
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
    // iOS 4 does not send -viewDidLayoutSubviews, so make sure the drawer's
    // subviews have real frames every time the player is shown.
    [self layoutPageSubviews];
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

// iOS 4 rotation: the modern layout callback never fires there, so re-lay out
// the drawers after the interface orientation changes.
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self layoutPageSubviews];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

// iOS 4/5 rotation goes through this method; the iOS 6+ ones below are ignored
// on the 3GS. Returning YES for every orientation keeps the dock layout and the
// drawer re-layout above reachable there.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

// The Now Playing tab is the only landscape-capable screen (the tab bar gates
// the rest to portrait): it drives the dock layout when the device is rotated.
- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    return (NSUInteger)UIInterfaceOrientationMaskAll;
}

#pragma mark - Refresh

- (void)refreshTrack {
    [self resetArtworkPresentation];
    self.generalPending = nil;
    self.generalFetched = NO;
    self.generalInfo = nil;
    // The fetch calls below, after the labels and artwork are set up, are the
    // only ones needed. Calling them here as well used to start two identical
    // request chains for every track change.
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

    self.outgoingArtworkImage = self.artworkView.image;
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
        __unsafe_unretained LTPlayerViewController *weakSelf = self;
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
    if (LTInfoDrawerAllowed()) {
        [self refreshLyricsForCurrentTrack];
        [self refreshGeneralInfoForCurrentTrack];
    }
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
    [LTTransitionSettings animateWithDuration:0.35 animations:^{
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
    [LTTransitionSettings animateWithDuration:0.35 animations:^{
        self.pagesHint.alpha = 0.0f;
        primary.alpha = 1.0f;
        secondary.alpha = 1.0f;
    } completion:^(BOOL finished) {
        self.pagesHint.hidden = YES;
        self.pagesHint.alpha = 1.0f;
    }];
}

- (BOOL)artworkBackgroundEnabled {
    return [LTArtworkBackground enabled];
}

// Create or remove the album-art background/scrim based on the current toggle.
// Called at load and again each time the view appears so changes apply live.
- (void)applyArtworkBackgroundPref {
    if (![self artworkBackgroundEnabled]) {
        [self.backgroundImageView removeFromSuperview];
        self.backgroundImageView = nil;
        [self.scrimView removeFromSuperview];
        self.scrimView = nil;
        self.gradientScrim = nil;
        self.view.backgroundColor = [UIColor blackColor];
        return;
    }
    self.view.backgroundColor = [LTTheme background];
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
// Short cross dissolve on a new image. Skipping with the transport keys used to
// hard-cut both the artwork and the backdrop, which was jarring on the 3GS where
// the change is instant and unmissable.
//
// Only crossfades when there is something already on screen; the very first
// image for a view is set outright so launch does not fade in from nothing.
- (void)crossfadeImageView:(UIImageView *)imageView toImage:(UIImage *)image {
    if (!imageView || !image) return;
    if (!imageView.image) {
        imageView.image = image;
        return;
    }
    if (![LTTransitionSettings animationsEnabled]) {
        imageView.image = image;
        return;
    }
    CGFloat duration = [LTTransitionSettings durationFor:0.28f];
    [UIView transitionWithView:imageView
                      duration:duration
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ imageView.image = image; }
                    completion:nil];
}

- (void)applyBackdropImage:(UIImage *)blurred palette:(NSArray *)palette {
    if (!blurred) return;
    [self crossfadeImageView:self.backgroundImageView toImage:blurred];
}

// Swapping the cover uses the same slide as the swipe gesture rather than a
// cross dissolve: the outgoing cover leaves one side while the incoming one
// arrives from the other, with the same scale-down and alpha ramp.
- (void)applyArtwork:(UIImage *)image forVideoId:(NSString *)videoId {
    if (!image) return;

    BOOL sameTrack = videoId.length && [videoId isEqualToString:self.artworkVideoId];
    NSInteger newIndex = [[LTPlayerController sharedController] currentIndex];
    NSInteger direction = (newIndex >= self.artworkTrackIndex) ? -1 : 1; // -1 = next
    self.artworkTrackIndex = newIndex;
    self.artworkVideoId = videoId;

    // The cover we are sliding out of, if refreshTrack blanked one.
    UIImage *outgoing = self.outgoingArtworkImage;
    self.outgoingArtworkImage = nil;

    // First cover for this view: nothing to slide away from.
    if (!outgoing && (!self.artworkView.image || !self.artworkView.superview)) {
        self.artworkView.image = image;
        return;
    }
    // The high-res replaces the thumbnail for the same track, and a disabled
    // animation setting both mean: swap it straight in rather than replaying
    // the slide for the same cover.
    if (sameTrack || ![LTTransitionSettings animationsEnabled]) {
        self.artworkView.image = image;
        return;
    }

    // Put the outgoing cover back for the duration of the slide.
    if (outgoing && !self.artworkView.image) {
        self.artworkView.image = outgoing;
    }

    CGFloat duration = 0.18f;
    CGFloat restX = self.panBaseX;
    CGFloat width = self.artworkView.bounds.size.width;
    CGFloat offX = restX + direction * width;

    self.incomingArtworkView.image = image;
    self.incomingArtworkView.center = CGPointMake(restX + direction * width, self.artworkView.center.y);
    self.incomingArtworkView.alpha = 0.0f;

    [LTTransitionSettings animateWithDuration:duration animations:^{
        self.artworkView.center = CGPointMake(offX, self.artworkView.center.y);
        self.artworkView.alpha = 0.0f;
        self.artworkView.transform = CGAffineTransformMakeScale(0.9f, 0.9f);
        self.incomingArtworkView.center = CGPointMake(restX, self.artworkView.center.y);
        self.incomingArtworkView.alpha = 1.0f;
    } completion:^(BOOL finished) {
        self.artworkView.image = image;
        [self resetArtworkPresentation];
    }];
}

- (void)setArtworkImage:(UIImage *)image forVideoId:(NSString *)videoId {
    if (!image) return;
    [self applyArtwork:image forVideoId:videoId];
    if (![self artworkBackgroundEnabled]) return;
    UIImage *blurred = [self.blurCache objectForKey:videoId];
    if (blurred) {
        [self applyBackdropImage:blurred
                         palette:[self.paletteCache objectForKey:videoId]];
        return;
    }
    __unsafe_unretained LTPlayerViewController *weakSelf = self;
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
        self.spinnerBackdrop.hidden = NO;
        self.spinnerBackdrop.frame = self.mainPane.bounds;
    } else {
        [self.spinner stopAnimating];
        self.spinnerBackdrop.hidden = YES;
    }
    self.stationMenuButton.hidden = YES;
    UIColor *glyphColor = [UIColor blackColor];
    if ([LTTheme isModern]) glyphColor = [LTTheme isDark] ? [UIColor whiteColor] : [UIColor blackColor];
    [self.playlistButton setTitle:@"\u22EF" forState:UIControlStateNormal];
    [self.playlistButton setImage:nil forState:UIControlStateNormal];
    self.playlistButton.titleLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    [self.playlistButton setTitleColor:glyphColor forState:UIControlStateNormal];
    // Remove only our own action, not every target: a blanket removeTarget:nil
    // also wipes the press-feedback target added in -addPressFeedbackToButton,
    // and on iOS 4 mutating a button's targets while it is being touched can
    // cancel the touch outright.
    [self.playlistButton removeTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.playlistButton addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];

    [self applyTransportImages];
}

// On the tall edge-to-edge layout the transport controls are drawn much larger,
// so they are rendered from the Font Awesome glyphs at the size they need rather
// than the fixed 30x30 bitmap assets. Older layouts keep the original bitmaps.
- (void)stationMenuTapped:(id)sender {
    if (self.pressGlow) self.pressGlow.alpha = 0.0f;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Station Options"
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Recommend more songs like this", @"Don't recommend songs like this", @"Prevent this song from playing on this station", nil];
    sheet.tag = 5555;
    [sheet showInView:self.view];
#if !__has_feature(objc_arc)
    [sheet release];
#endif
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == 7777) {
        LTPlayerController *pc = [LTPlayerController sharedController];
        LTTrack *current = [pc currentTrack];
        // button 0 = Add to Playlist
        if (buttonIndex == 0) {
            [self addToPlaylistTapped];
            return;
        }
        NSInteger idx = 1;
        if ([pc radioEnabled]) {
            if (buttonIndex == idx) {
                // Recommend more songs like this
                if (current) {
                    [[LTYouTubeClient sharedClient] fetchRadioForTrack:current completion:^(NSArray *tracks, NSError *error) {
                        if (tracks.count) {
                            NSMutableArray *toAdd = [NSMutableArray array];
                            for (LTTrack *t in tracks) {
                                if ([pc isStationBlacklistedVideoId:t.videoId]) continue;
                                BOOL exists = NO;
                                for (LTTrack *q in pc.queue) {
                                    if ([q.videoId isEqualToString:t.videoId]) { exists = YES; break; }
                                }
                                if (!exists) [toAdd addObject:t];
                            }
                            if (toAdd.count) [pc enqueueTracks:toAdd];
                        }
                    }];
                }
                return;
            }
            idx++;
            if (buttonIndex == idx) {
                // Don't recommend songs like this
                if (current) [pc blacklistVideoIdForCurrentStation:current.videoId];
                [pc nextTrack];
                return;
            }
            idx++;
            if (buttonIndex == idx) {
                // Prevent this song from playing on this station
                if (current) [pc blacklistVideoIdForCurrentStation:current.videoId];
                NSInteger i = pc.currentIndex;
                if (i >= 0 && i < (NSInteger)pc.queue.count) {
                    [pc removeTrackAtIndex:i];
                }
                return;
            }
        }
        return;
    }
    // legacy tag 5555 (no longer used)
    if (actionSheet.tag != 5555) return;
}

- (void)applyTransportImages {
    LTPlayerController *controller = [LTPlayerController sharedController];

    // The glyph colours. The modern themes restyle them: light on the dark
    // theme, dark on the light one, and the accent colour when shuffle or
    // repeat is on. The native theme keeps black and its blue.
    UIColor *resting = [UIColor blackColor];
    UIColor *highlight = [UIColor colorWithRed:0.349f green:0.678f blue:1.0f alpha:1.0f];
    if ([LTTheme isModern]) {
        resting = [LTTheme isDark] ? [UIColor whiteColor] : [UIColor blackColor];
        highlight = [LTTheme accent];
    }

    if ([self isTallScreen] || [self isSideBySide]) {
        BOOL pad = [self isIPad];
        BOOL sb = [self isSideBySide];
        // Circles are big on the tall layout and very big in iPad side-by-side,
        // so the glyphs inside stay relatively small for a cleaner ring.
        CGFloat prevNextGlyph = pad ? (sb ? 26.0f : 52.0f) : 34.0f;
        CGFloat smallGlyph = pad ? (sb ? 22.0f : 52.0f) : 34.0f;
        CGFloat playGlyph = pad ? (sb ? 40.0f : 84.0f) : 56.0f;
        UIColor *normal = resting;
        UIColor *highlighted = highlight;

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
        // The bundled bitmaps are in one fixed colour, so the modern themes
        // recolour them the same way they recolour the Lucide glyphs.
        if ([LTTheme isModern]) {
            repeatNormal = LTTintedImage(repeatNormal, normal);
            repeatSelected = LTTintedImage(repeatSelected, highlighted);
            repeatOneNormal = LTTintedImage(repeatOneNormal, normal);
            repeatOneSelected = LTTintedImage(repeatOneSelected, highlighted);
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
    UIColor *black = resting;
    UIColor *blue = highlight;

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
    if (LTInfoDrawerAllowed()) [self refreshLyricsForCurrentTrack];
}

- (void)queueDidChange:(NSNotification *)notification {
    [self refreshControls];
    [self reloadQueue];
    // On iOS 5 and earlier the queue drawer is sized to its rows, so a change in
    // track count has to re-lay out the pane as well as reload the table.
    if (!LTInfoDrawerAllowed() && self.view.bounds.size.height >= 1.0f) {
        [self layoutPages];
        [self layoutPageSubviews];
    }
    if (LTInfoDrawerAllowed()) [self refreshLyricsForCurrentTrack];
}

#pragma mark - Finger-tracked page sliding

// The page views. Lyrics and General are scroll views; Video is a fixed surface, so
// this is typed as UIView and only frames and visibility are touched here.
- (UIView *)infoPageViewAtIndex:(NSInteger)index {
    if (index == 0) return self.lyricsScroll;
    if (index == 1) return self.generalScroll;
    return nil;
}

// YES while any page pan is tracking. Checked across the set because the
// recognisers live on the individual page views, so there is no single instance to
// ask.
- (BOOL)anyInfoPagePanActive {
    for (UIPanGestureRecognizer *pan in self.infoPagePans) {
        if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
            return YES;
        }
    }
    return NO;
}

// Puts every page back at the base frame and shows only the selected one.
- (void)resetInfoPageFramesKeepingPage:(NSInteger)page {
    for (NSInteger i = 0; i < 2; i++) {
        UIView *view = [self infoPageViewAtIndex:i];
        if (!view) continue;
        view.frame = self.infoPageBaseFrame;
        view.hidden = (i != page);
    }
}

- (void)showInfoPage:(NSInteger)index {
    [self showInfoPage:index animated:YES];
}

- (void)showInfoPage:(NSInteger)index animated:(BOOL)animated {
    NSInteger page = MAX(0, MIN(index, 1));
    NSInteger previous = self.infoPageCurrent;
    LTLog(@"DRAWER show page=%d from=%d animated=%d settling=%d base=%.0fx%.0f seg=%ld",
          (int)page, (int)previous, animated, self.infoPageSettling ? 1 : 0,
          (double)self.infoPageBaseFrame.size.width, (double)self.infoPageBaseFrame.size.height,
          (long)self.infoPageControl.selectedSegmentIndex);
    if (page == previous) {
        [self resetInfoPageFramesKeepingPage:page];
        return;
    }
    if (page == 1) [self refreshGeneralInfoForCurrentTrack];

    CGFloat w = self.infoPageBaseFrame.size.width;
    if (!animated || self.infoPageSettling || w < 1.0f) {
        self.infoPageCurrent = page;
        self.infoPageControl.selectedSegmentIndex = page;
        [self resetInfoPageFramesKeepingPage:page];
        return;
    }

    // Slide in from the side the page sits on, so tapping the segment control reads
    // the same way as dragging.
    CGFloat from = (page > previous) ? w : -w;
    UIView *incoming = [self infoPageViewAtIndex:page];
    UIView *outgoing = [self infoPageViewAtIndex:previous];
    incoming.frame = CGRectOffset(self.infoPageBaseFrame, from, 0);
    incoming.hidden = NO;
    self.infoPageSettling = YES;
    [LTTransitionSettings animateWithDuration:0.24
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        incoming.frame = self.infoPageBaseFrame;
        outgoing.frame = CGRectOffset(self.infoPageBaseFrame, -from, 0);
    } completion:^(BOOL finished) {
        self.infoPageSettling = NO;
        self.infoPageCurrent = page;
        self.infoPageControl.selectedSegmentIndex = page;
        [self resetInfoPageFramesKeepingPage:page];
    }];
}

- (void)infoPageChanged:(UISegmentedControl *)control {
    LTLog(@"DRAWER segment changed to %d", (int)control.selectedSegmentIndex);
    [self showInfoPage:control.selectedSegmentIndex animated:YES];
}

- (void)infoPagePanned:(UIPanGestureRecognizer *)pan {
    if (self.infoPageSettling) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.infoPageBaseFrame = self.lyricsScroll.frame;
    }
    CGRect base = self.infoPageBaseFrame;
    CGFloat w = base.size.width;
    if (w < 1.0f) return;

    if (pan.state == UIGestureRecognizerStateBegan) {
        NSInteger current = self.infoPageCurrent;
        self.infoPageDragFrom = current;
        CGPoint v = [pan velocityInView:self.statsPane];
        NSInteger neighbor = (v.x < 0) ? current + 1 : current - 1;
        if (neighbor < 0 || neighbor > 1) neighbor = current;
        self.infoPageNeighbor = neighbor;
        if (neighbor != current) {
            UIView *page = [self infoPageViewAtIndex:current];
            if ([page isKindOfClass:[UIScrollView class]]) {
                [(UIScrollView *)page setContentOffset:CGPointZero animated:NO];
            }
        }
        return;
    }

    NSInteger from = self.infoPageDragFrom;
    NSInteger to = self.infoPageNeighbor;
    CGFloat dx = [pan translationInView:self.statsPane].x;
    if (dx > w) dx = w;
    if (dx < -w) dx = -w;
    UIView *a = [self infoPageViewAtIndex:from];
    UIView *b = [self infoPageViewAtIndex:to];
    BOOL sliding = (b && b != a);

    if (pan.state == UIGestureRecognizerStateChanged) {
        LTLog(@"DRAWER pan x=%.0f from=%ld to=%ld", (double)dx, (long)from, (long)to);
        if (sliding) {
            a.frame = CGRectOffset(base, dx, 0);
            b.frame = CGRectOffset(base, dx + ((dx < 0) ? w : -w), 0);
        }
        return;
    }

    // Settle on release: past a third of the width, or a flick.
    BOOL commit = NO;
    if (sliding) {
        CGPoint v = [pan velocityInView:self.statsPane];
        if (dx < -w / 3.0f || v.x < -600.0f) commit = YES;
        if (dx > w / 3.0f || v.x > 600.0f) commit = YES;
    }
    NSInteger target = commit ? to : from;
    self.infoPageSettling = YES;
    [LTTransitionSettings animateWithDuration:0.20
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        if (sliding) {
            a.frame = CGRectMake(base.origin.x + (commit ? (dx < 0 ? -w : w) : dx), base.origin.y, base.size.width, base.size.height);
            b.frame = commit ? base : CGRectOffset(base, dx, 0);
        }
    } completion:^(BOOL finished) {
        self.infoPageSettling = NO;
        self.infoPageCurrent = target;
        self.infoPageControl.selectedSegmentIndex = target;
        [self resetInfoPageFramesKeepingPage:target];
    }];
    self.infoPageDragFrom = target;
    self.infoPageNeighbor = target;
    self.infoPageCurrent = target;
}

#pragma mark - Info drawer pages

- (void)refreshGeneralInfoForCurrentTrack {
    if (!self.generalScroll) return;
    LTTrack *track = [[LTPlayerController sharedController] currentTrack];
    if (!track) {
        self.generalVideoId = nil;
        self.generalInfo = nil;
        [self showGeneralMessage:@"Nothing playing.\n\nSwipe up for info\nonce a song starts."];
        return;
    }
    // Show what the app already knows straight away. The YouTube extras are a bonus
    // layered on top, so a blocked or unavailable video leaves a populated page
    // rather than an error.
    if (!self.generalFetched) {
        // Render the local metadata immediately, before any network work, so the
        // page always has content. The YouTube fields are merged in on top of this
        // when a fetch succeeds; if it fails, this stays on screen instead of an
        // error message.
        NSMutableDictionary *local = [NSMutableDictionary dictionary];
        if (track.title.length) [local setObject:track.title forKey:@"title"];
        if (track.artist.length) [local setObject:track.artist forKey:@"uploader"];
        [local setObject:@"1" forKey:@"localOnly"];
        [self renderGeneralInfo:local];
    }
    if (!track.videoId.length) {
        self.generalVideoId = nil;
        return;
    }
    if ([self.generalVideoId isEqualToString:track.videoId] &&
        (self.generalFetched || self.generalFetching)) {
        return;
    }
    // Reset the cached id so a failed fetch is retried on the next track rather
    // than being remembered as "already loaded".
    self.generalVideoId = track.videoId;
    self.generalFetching = YES;
    [self showGeneralMessage:@"Loading\u2026"];
    __unsafe_unretained LTPlayerViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] fetchVideoGeneralInfoForVideoId:track.videoId
                                                          completion:^(NSDictionary *info, NSError *error) {
        LTPlayerViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.generalFetching = NO;
        if (![[[LTPlayerController sharedController] currentTrack].videoId isEqualToString:track.videoId]) {
            return;
        }
        if (error || !info.count) {
            LTLog(@"GENERAL failed videoId=%@ error=%@", track.videoId, error);
            strongSelf.generalFetched = YES;
            strongSelf.generalVideoId = nil;
            return;   // keep whatever local metadata is already on screen
        }
        {
        }
        strongSelf.generalInfo = info;
        strongSelf.generalFetched = YES;
        LTLog(@"GENERAL result videoId=%@ fields=%@",
              track.videoId, [[info allKeys] componentsJoinedByString:@","]);
        [strongSelf renderGeneralInfo:info];
    }];
}

- (void)showGeneralMessage:(NSString *)message {
    for (UIView *sub in self.generalScroll.subviews) [sub removeFromSuperview];
    CGRect gbox = self.generalScroll.bounds;
    if (gbox.size.width < 1.0f || gbox.size.height < 1.0f) {
        gbox = self.infoPageBaseFrame;
        if (gbox.size.width < 1.0f) gbox = CGRectMake(0, 0, 200, 100);
    }
    UILabel *label = [[UILabel alloc] initWithFrame:gbox];
    label.tag = 88;
    label.text = message;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = [self drawerSecondaryTextColor];
    label.backgroundColor = [UIColor clearColor];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.generalScroll addSubview:label];
    self.generalScroll.contentSize = CGSizeMake(gbox.size.width, gbox.size.height);
}

- (NSString *)generalDurationText:(NSString *)seconds {
    NSInteger total = seconds.integerValue;
    if (total <= 0) return nil;
    NSInteger h = total / 3600;
    NSInteger m = (total % 3600) / 60;
    NSInteger s = total % 60;
    if (h > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)h, (long)m, (long)s];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)m, (long)s];
}

- (void)renderGeneralInfo:(NSDictionary *)info {
    if (!self.generalScroll) return;
    for (UIView *sub in self.generalScroll.subviews) [sub removeFromSuperview];

    CGFloat w = self.generalScroll.bounds.size.width;
    if (w < 1.0f) {
        self.generalPending = info;
        LTLog(@"GENERAL defer render, scroll width=0");
        return;
    }
    CGFloat inset = 16.0f;
    CGFloat inner = w - inset * 2.0f;
    CGFloat y = 16.0f;

    NSString *uploader = [info objectForKey:@"uploader"];
    NSString *avatarURL = [info objectForKey:@"avatarURL"];
    if (avatarURL.length) {
        self.generalAvatar = [[UIImageView alloc] initWithFrame:CGRectMake(0, y, 64, 64)];
        self.generalAvatar.backgroundColor = [LTTheme isModern]
            ? [LTTheme fill]
            : [UIColor colorWithWhite:0.16f alpha:1.0f];
        self.generalAvatar.contentMode = UIViewContentModeScaleAspectFill;
        self.generalAvatar.clipsToBounds = YES;
        self.generalAvatar.layer.cornerRadius = 32.0f;
        [self.generalScroll addSubview:self.generalAvatar];
        __unsafe_unretained LTPlayerViewController *weakSelf = self;
        [[LTYouTubeClient sharedClient] loadImageWithURL:avatarURL completion:^(UIImage *image) {
            if (image) weakSelf.generalAvatar.image = image;
        }];
    }

    // The heading is the video's own title, not the uploader. Titles are long and
    // wrap, so its height is measured rather than fixed, and the uploader still
    // appears in the rows below.
    NSString *title = [info objectForKey:@"title"];
    UIFont *titleFont = [UIFont boldSystemFontOfSize:17];
    CGFloat titleH = 0.0f;
    if (title.length) {
        CGSize titleSize = [title sizeWithFont:titleFont
                           constrainedToSize:CGSizeMake(inner, CGFLOAT_MAX)
                                lineBreakMode:NSLineBreakByWordWrapping];
        titleH = MAX(22.0f, ceilf(titleSize.height));
    }
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(inset, y, inner, titleH)];
    name.text = title.length ? title : @"";
    name.numberOfLines = 0;
    name.lineBreakMode = NSLineBreakByWordWrapping;
    name.font = titleFont;
    name.textColor = [self drawerTextColor];
    name.backgroundColor = [UIColor clearColor];
    [self.generalScroll addSubview:name];
    y += titleH + 8.0f;

    NSString *duration = [self generalDurationText:[info objectForKey:@"durationSeconds"]];
    if (duration.length) {
        UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(inset, y, inner, 18)];
        sub.text = duration;
        sub.font = [UIFont systemFontOfSize:13];
        sub.textColor = [self drawerFaintTextColor];
        sub.backgroundColor = [UIColor clearColor];
        [self.generalScroll addSubview:sub];
        y += 24.0f;
    }

    y += 6.0f;
    NSMutableArray *rows = [NSMutableArray array];
    if (uploader.length) [rows addObject:[NSArray arrayWithObjects:@"Uploaded by", uploader, nil]];
    LTTrack *current = [[LTPlayerController sharedController] currentTrack];
    if (current.album.length && ![current.album isEqualToString:uploader]) {
        [rows addObject:[NSArray arrayWithObjects:@"Album", current.album, nil]];
    }
    if ([info objectForKey:@"localOnly"] && ![info objectForKey:@"viewCount"]) {
        [rows addObject:[NSArray arrayWithObjects:@"YouTube info",
                         @"Unavailable for this track", nil]];
    }
    NSString *views = [info objectForKey:@"viewCount"];
    if (views.length) [rows addObject:[NSArray arrayWithObjects:@"Views", views, nil]];
    NSString *likes = [info objectForKey:@"likeCount"];
    if (likes.length) [rows addObject:[NSArray arrayWithObjects:@"Likes", likes, nil]];
    if (duration.length) [rows addObject:[NSArray arrayWithObjects:@"Duration", duration, nil]];

    for (NSArray *row in rows) {
        NSString *key = [row objectAtIndex:0];
        NSString *value = [row objectAtIndex:1];

        UILabel *k = [[UILabel alloc] initWithFrame:CGRectMake(inset, y, 104, 20)];
        k.text = key;
        k.font = [UIFont systemFontOfSize:13];
        k.textColor = [self drawerFaintTextColor];
        k.backgroundColor = [UIColor clearColor];
        [self.generalScroll addSubview:k];

        UIFont *vFont = [UIFont systemFontOfSize:15];
        CGSize measured = [value sizeWithFont:vFont
                           constrainedToSize:CGSizeMake(inner - 110.0f, CGFLOAT_MAX)
                                lineBreakMode:NSLineBreakByWordWrapping];
        CGFloat vh = MAX(20.0f, ceilf(measured.height));
        UILabel *v = [[UILabel alloc] initWithFrame:CGRectMake(inset + 110.0f, y, inner - 110.0f, vh)];
        v.text = value;
        v.font = vFont;
        v.numberOfLines = 0;
        v.textColor = [self drawerTextColor];
        v.backgroundColor = [UIColor clearColor];
        [self.generalScroll addSubview:v];

        y += MAX(26.0f, vh + 6.0f);
    }

    self.generalScroll.contentSize = CGSizeMake(w, y + 16.0f);
    LTLog(@"GENERAL rendered width=%.0f height=%.0f subviews=%d", w, y + 16.0f, (int)self.generalScroll.subviews.count);
}

#pragma mark - Lyrics

- (void)refreshLyricsForCurrentTrack {
    if (!self.lyricsScroll) return;
    LTTrack *track = [[LTPlayerController sharedController] currentTrack];
    if (!track || !track.videoId.length) {
        self.lyricsVideoId = nil;
        self.lyricLines = nil;
        [self showLyricsMessage:@"Nothing playing.\n\nSwipe up for info\nonce a song starts."];
        return;
    }
    if ([self.lyricsVideoId isEqualToString:track.videoId]) {
        return;
    }
    self.lyricsVideoId = track.videoId;
    self.lyricLines = nil;

    // Cache first. Lyrics are immutable per video, so once seen they never need
    // fetching again -- this makes the pane work offline and removes the
    // "Loading lyrics" pause on every track.
    NSDictionary *cached = [[LTPlaylistStore sharedStore] cachedLyricsForVideoId:track.videoId];
    if (cached) {
        [self applyLyricsPayload:cached forVideoId:track.videoId];
        return;
    }

    [self showLyricsMessage:@"Loading lyrics\u2026"];
    __unsafe_unretained LTPlayerViewController *weakSelf = self;
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
        // Remember the result, including a song that simply has no lyrics, so we
        // do not ask again on every play.
        [[LTPlaylistStore sharedStore] cacheLyrics:result forVideoId:track.videoId];
        [strongSelf applyLyricsPayload:result forVideoId:track.videoId];
    }];
}

// Render a lyrics payload, whether it came from disk or the network.
- (void)applyLyricsPayload:(NSDictionary *)result forVideoId:(NSString *)videoId {
    self.lyricLines = nil;
    BOOL timed = [[result objectForKey:@"hasTimestamps"] boolValue];
    NSArray *lines = [result objectForKey:@"lines"];
    if (timed && [lines isKindOfClass:[NSArray class]] && lines.count) {
        self.lyricLines = lines;
        self.lyricsVideoId = videoId;
        [self renderLyricLinesAnimated:NO];
        [self updateLyricHighlightForTime:[[LTPlayerController sharedController] currentTime]];
        return;
    }
    NSString *plain = [result objectForKey:@"lyrics"];
    if ([plain isKindOfClass:[NSString class]] && plain.length) {
        self.lyricsVideoId = videoId;
        self.lyricsPlainText = plain;
        [self showPlainLyrics:plain];
    } else {
        self.lyricsVideoId = nil;
        [self showLyricsMessage:@"No lyrics available\nfor this song."];
    }
}

// Lays the lyrics out again for the width the drawer is now.
//
// The lines are laid out for the width they were loaded at, and the drawer in
// landscape is much narrower than the one in portrait, so the text ran off the
// side of it and away from the centre. Re-laying them out keeps each line
// centred in the drawer it is in.
- (void)relayoutLyrics {
    if (!self.lyricsScroll) return;
    CGFloat width = CGRectGetWidth(self.lyricsScroll.bounds);
    if (width < 1.0f) return;
    if (fabs(width - self.lyricsLayoutWidth) < 0.5f) return;
    self.lyricsLayoutWidth = width;

    CGPoint offset = self.lyricsScroll.contentOffset;
    if (self.lyricLines.count) {
        [self renderLyricLinesAnimated:NO];
    } else if (self.lyricsPlainText.length) {
        [self showPlainLyrics:self.lyricsPlainText];
    } else {
        return;   // the message, which is laid out by its autoresizing mask
    }
    self.lyricsScroll.contentOffset = offset;
    [self updateLyricHighlightForTime:[[LTPlayerController sharedController] currentTime]];
}

// The colour of a lyric line that is not being sung.
//
// On the skeuomorphic systems the lyrics are ink on paper rather than light
// on the dark drawer, so the colour follows the paper.
- (UIColor *)lyricIdleColor {
    if ([LTTheme usesSkeuomorphicSurfaces]) {
        return [UIColor colorWithRed:0.29f green:0.26f blue:0.21f alpha:1.0f];
    }
    if ([LTTheme isModern]) return [LTTheme secondaryText];
    return [UIColor colorWithWhite:0.55f alpha:1.0f];
}

// The colour of the line being sung.
- (UIColor *)lyricActiveColor {
    if ([LTTheme usesSkeuomorphicSurfaces]) {
        return [LTTheme accent];
    }
    if ([LTTheme isModern]) return [LTTheme text];
    return [UIColor whiteColor];
}

// The sheet of paper under the lyrics, sized to the text.
- (void)layoutLyricsPaper {
    if (!self.lyricsPaper) return;
    CGSize size = self.lyricsScroll.contentSize;
    CGFloat inset = 6.0f;
    CGRect frame = CGRectMake(inset, 6.0f, size.width - inset * 2.0f, size.height - 12.0f);
    if (frame.size.height < 48.0f) frame.size.height = 48.0f;
    self.lyricsPaper.frame = frame;
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
    label.textColor = [LTTheme usesSkeuomorphicSurfaces]
        ? [UIColor colorWithRed:0.40f green:0.37f blue:0.31f alpha:1.0f]
        : [self drawerSecondaryTextColor];
    label.backgroundColor = [UIColor clearColor];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.lyricsScroll addSubview:label];
    // Only the lyrics go. The sheet of paper stays.
    for (UIView *sub in self.lyricsScroll.subviews) {
        if (sub != label && sub != self.lyricsPaper) [sub removeFromSuperview];
    }
    self.lyricsScroll.contentSize = self.lyricsScroll.bounds.size;
    [self layoutLyricsPaper];
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
        label.textColor = [LTTheme usesSkeuomorphicSurfaces]
            ? [self lyricIdleColor]
            : [self drawerSecondaryTextColor];
        label.backgroundColor = [UIColor clearColor];
        [self.lyricsScroll addSubview:label];
        [labels addObject:label];
        y += h + lineHeight;
    }
    self.lyricLabelViews = labels;
    self.lyricsScroll.contentSize = CGSizeMake(w + inset * 2.0f, y + 14.0f);
    self.lyricsLayoutWidth = CGRectGetWidth(self.lyricsScroll.bounds);
    [self layoutLyricsPaper];
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
        label.textColor = [self lyricIdleColor];
        label.backgroundColor = [UIColor clearColor];
        [self.lyricsScroll addSubview:label];
        [labels addObject:label];
        y += h + gap;
    }
    self.lyricLabelViews = labels;
    self.lyricsScroll.contentSize = CGSizeMake(w + inset * 2.0f, y + 16.0f);
    self.lyricsLayoutWidth = CGRectGetWidth(self.lyricsScroll.bounds);
    [self layoutLyricsPaper];
}

- (void)updateLyricHighlightForTime:(NSTimeInterval)time {
    if (!self.lyricLines.count || !self.lyricLabelViews.count) return;
    // User calibration: YouTube's LRC timestamps are often a few hundred ms out.
    NSTimeInterval ms = (time + LTLyricsOffset()) * 1000.0;
    NSInteger index = -1;
    for (NSInteger i = 0; i < (NSInteger)self.lyricLines.count; i++) {
        NSDictionary *line = [self.lyricLines objectAtIndex:(NSUInteger)i];
        NSTimeInterval start = [[line objectForKey:@"start"] doubleValue];
        NSTimeInterval end = [[line objectForKey:@"end"] doubleValue];
        if (ms >= start && ms < end) { index = i; break; }
    }
    if (index == self.activeLyricIndex) return;
    self.activeLyricIndex = index;
    UIColor *activeColor = [self lyricActiveColor];
    UIColor *idleColor = [self lyricIdleColor];
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
        cell.textLabel.textColor = [self drawerTextColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.textColor = [self drawerSecondaryTextColor];
        cell.showsReorderControl = YES;
    }
    LTPlayerController *controller = [LTPlayerController sharedController];
    LTTrack *track = [[controller queue] objectAtIndex:(NSUInteger)indexPath.row];
    NSInteger idx = (NSInteger)indexPath.row;
    cell.imageView.image = nil;
    if (idx == controller.currentIndex) {
        cell.imageView.image = [self scaledQueueIcon:[LTGraphics glyphIcon:0xF04B
                                                                      size:20.0f
                                                                     color:[self drawerHighlightColor]]];
        cell.imageView.contentMode = UIViewContentModeCenter;
        cell.textLabel.text = track.title;
        cell.textLabel.textColor = [self drawerHighlightColor];
    } else {
        cell.textLabel.text = [NSString stringWithFormat:@"%d. %@", (int)idx + 1, track.title];
        cell.textLabel.textColor = [self drawerTextColor];
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
    // The glyph marks the track that is playing. In the modern themes it
    // goes in the gutter to the left of the card, so it is a little bigger
    // than the plain list's, and it has to leave a gap between it and the
    // card's edge.
    CGSize size = CGSizeMake(16.0f, 16.0f);
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
