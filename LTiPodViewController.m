#import "LTiPodViewController.h"
#import "LTAppDelegate.h"
#import "LTPlaylistStore.h"
#import "LTPlayerController.h"
#import "LTYouTubeClient.h"
#import "LTModel.h"
#import "LTGraphics.h"
#import "LTLog.h"
#import "LTSafeArea.h"
#import <math.h>
#import <AudioToolbox/AudioToolbox.h>
#import <dlfcn.h>
#import <MediaPlayer/MediaPlayer.h>

static UIFont *LTiPodFAFont(CGFloat size) {
    return [LTGraphics fontAwesomeFontWithSize:size];
}

// Minimum wheel rotation (degrees) before a scroll step is sent to the list.
static const CGFloat kIPodScrollMinDegrees = 4.0f;

// Generates a short synthetic UI click as a mono 16-bit PCM WAV.
static void LTWriteToneWAV(NSString *path, double f1, double amp1, double f2, double amp2,
                           double decay, double durationSec) {
    NSInteger rate = 22050;
    NSInteger frames = (NSInteger)((double)rate * durationSec);
    NSMutableData *wav = [NSMutableData dataWithCapacity:(NSUInteger)(44 + frames * 2)];
    uint32_t bits = 16;
    uint32_t bytesPerSec = (uint32_t)(rate * bits / 8);
    uint16_t blockAlign = (uint16_t)(bits / 8);
    [wav appendBytes:"RIFF" length:4];
    uint32_t chunk = (uint32_t)(36 + frames * 2);
    [wav appendBytes:&chunk length:4];
    [wav appendBytes:"WAVEfmt " length:8];
    uint32_t sixteen = 16;
    [wav appendBytes:&sixteen length:4];
    uint16_t pcm = 1, mono = 1;
    [wav appendBytes:&pcm length:2];
    [wav appendBytes:&mono length:2];
    uint32_t r = (uint32_t)rate;
    [wav appendBytes:&r length:4];
    [wav appendBytes:&bytesPerSec length:4];
    [wav appendBytes:&blockAlign length:2];
    [wav appendBytes:&bits length:2];
    [wav appendBytes:"data" length:4];
    uint32_t dsz = (uint32_t)(frames * 2);
    [wav appendBytes:&dsz length:4];
    for (NSInteger i = 0; i < frames; i++) {
        double t = (double)i / rate;
        double env = exp(-t * decay);
        double s = sin(2.0 * M_PI * f1 * t) * amp1 + sin(2.0 * M_PI * f2 * t) * amp2;
        int16_t v = (int16_t)(s * env * 26000.0);
        [wav appendBytes:&v length:2];
    }
    [wav writeToFile:path atomically:YES];
}

// --------------------------------------------------- Search keyboard layout ----
// QWERTY keyboard: 30 keys in 4 rows (10 + 9 + 7 letters, then a row of
// Del / Space / Clr / Go action keys). Flat row-major index = wheel position.
static const CGFloat kSearchKeyH = 15.0f;
static const CGFloat kSearchKeyGap = 3.0f;
static const CGFloat kSearchMargin = 6.0f;

static NSUInteger LTiPodSearchKeyCount(void) { return 30; }

static NSUInteger LTiPodSearchRowCount(NSUInteger row) {
    static const NSUInteger rows[4] = {10, 9, 7, 4};
    return rows[row];
}

static CGFloat LTiPodSearchKeyboardTop(CGFloat height) {
    return height - (4 * kSearchKeyH + 3 * kSearchKeyGap + 8.0f);
}

static NSString *LTiPodSearchKeyLabel(NSUInteger idx) {
    static NSArray *letterRows = nil;
    if (!letterRows) letterRows = @[@"QWERTYUIOP", @"ASDFGHJKL", @"ZXCVBNM"];
    NSUInteger base = 0;
    for (NSUInteger row = 0; row < 3; row++) {
        NSString *s = [letterRows objectAtIndex:row];
        if (idx < base + s.length) {
            return [s substringWithRange:NSMakeRange(idx - base, 1)];
        }
        base += s.length;
    }
    switch (idx) {
        case 26: return @"Del";
        case 27: return @"Space";
        case 28: return @"Clr";
        case 29: return @"Go";
    }
    return @"";
}

static NSInteger LTiPodSearchKeyAction(NSUInteger idx) {
    if (idx < 26) return 0;           // letter
    switch (idx) {
        case 26: return 1;            // backspace
        case 27: return 2;            // space
        case 28: return 3;            // clear
        case 29: return 4;            // go
    }
    return 0;
}

static void LTiPodSearchKeyRect(NSUInteger idx, CGSize size, CGRect *outRect) {
    NSUInteger row = 0;
    NSUInteger base = 0;
    for (row = 0; row < 4; row++) {
        NSUInteger cnt = LTiPodSearchRowCount(row);
        if (idx < base + cnt) break;
        base += cnt;
    }
    NSUInteger col = idx - base;
    NSUInteger n = LTiPodSearchRowCount(row);
    CGFloat top = LTiPodSearchKeyboardTop(size.height) + (CGFloat)row * (kSearchKeyH + kSearchKeyGap);
    CGFloat inner = size.width - 2.0f * kSearchMargin;
    CGFloat kw = (inner - (CGFloat)(n - 1) * kSearchKeyGap) / (CGFloat)n;
    CGFloat rowW = (CGFloat)n * kw + (CGFloat)(n - 1) * kSearchKeyGap;
    CGFloat x = kSearchMargin + (size.width - rowW) / 2.0f + (CGFloat)col * (kw + kSearchKeyGap);
    *outRect = CGRectMake(x, top, kw, kSearchKeyH);
}

NSString *const LTiPodModeEnabledKey = @"LTiPodModeEnabled";

// ---------------------------------------------------------------- Model -----

typedef NS_ENUM(NSInteger, LTiPodAction) {
    LTiPodActionNone = 0,
    LTiPodActionSubmenu,        // has children; children built from store on push
    LTiPodActionSubmenuStatic,  // children provided by a block (no store access)
    LTiPodActionPlay,           // play item.tracks from item.playIndex
    LTiPodActionShuffleAll,
    LTiPodActionNowPlaying,
    LTiPodActionSearchLibrary,
    LTiPodActionSearchYouTube,
    LTiPodActionToggleVibrations,
    LTiPodActionToggleClickSound,
    LTiPodActionExit,
};

@interface LTiPodItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, assign) LTiPodAction action;
@property (nonatomic, assign) NSInteger playIndex;
@property (nonatomic, strong) NSArray *tracks;
@property (nonatomic, assign) BOOL nowPlayingRow; // left icon shows play symbol
@property (nonatomic, assign) unichar faIcon;      // Font Awesome glyph for the row (0 = music note)
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle action:(LTiPodAction)action;
@end

@implementation LTiPodItem
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle action:(LTiPodAction)action {
    if ((self = [super init])) {
        _title = title;
        _subtitle = subtitle;
        _action = action;
        _playIndex = 0;
        _faIcon = 0xF001; // music note
    }
    return self;
}
+ (LTiPodItem *)submenu:(NSString *)title {
    return [[LTiPodItem alloc] initWithTitle:title subtitle:nil action:LTiPodActionSubmenu];
}
+ (LTiPodItem *)playItemForTrack:(LTTrack *)track tracks:(NSArray *)tracks index:(NSInteger)index {
    LTiPodItem *item = [[LTiPodItem alloc] initWithTitle:track.title.length ? track.title : @"Unknown Song"
                                                subtitle:track.artist action:LTiPodActionPlay];
    item.playIndex = index;
    item.tracks = tracks;
    return item;
}
@end

// A pane shown on the LCD: either a scrolling list or a now-playing/info view.
@interface LTiPodPane : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray *items;   // for LTiPodPaneKindList
@property (nonatomic, assign) BOOL isNowPlaying; // for LTiPodPaneKindNowPlaying
@property (nonatomic, assign) BOOL isSearch;      // search keyboard pane
@property (nonatomic, assign) BOOL isInfo;       // static info rows (no scrolling art)
@end

@implementation LTiPodPane
@end

// ----------------------------------------------------------- LCD views ------

// Scrolling list with a fixed highlight bar at the top (iPod classic behaviour).
@interface LTiPodListView : UIView
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, assign) CGFloat contentOffset;   // points scrolled into items
@property (nonatomic, assign) BOOL showsChevrons;      // trailing ">" for submenu rows
@property (nonatomic, readonly) NSInteger selectedIndex;
+ (CGFloat)rowHeight;
+ (NSInteger)visibleRows;
- (void)setContentOffsetImmediate:(CGFloat)offset;
- (void)snapSelection;
@end

// Now-playing pane: artwork, title/artist/album, progress bar + times.
@interface LTiPodNowPlayingView : UIView
@property (nonatomic, strong) LTTrack *track;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) NSTimeInterval elapsed;
@property (nonatomic, assign) NSTimeInterval total;
@property (nonatomic, strong) UIImage *artImage;
@property (nonatomic, assign) CGFloat volume;   // 0..1
@property (nonatomic, assign) BOOL volumeMode;  // volume bar shown instead of progress bar
@end

// Search pane: QWERTY keyboard with a type-ahead results strip on top.
@interface LTiPodSearchView : UIView
@property (nonatomic, copy) NSString *query;
@property (nonatomic, strong) NSArray *results;    // LTTrack* type-ahead matches
@property (nonatomic, assign) NSInteger keyIndex;  // highlighted key
@property (nonatomic, assign) BOOL loading;        // network search in flight
@end

// ----------------------------------------------------------- Click wheel ----

typedef NS_ENUM(NSInteger, LTiPodWheelButton) {
    LTiPodWheelButtonMenu = 0,
    LTiPodWheelButtonPrevious,
    LTiPodWheelButtonPlayPause,
    LTiPodWheelButtonNext,
    LTiPodWheelButtonSelect,
    LTiPodWheelButtonNone,   // nothing to act on (scroll band)
};

@class LTiPodWheelView;
@protocol LTiPodWheelDelegate <NSObject>
- (void)iPodWheel:(LTiPodWheelView *)wheel buttonPressed:(LTiPodWheelButton)button;
- (void)iPodWheel:(LTiPodWheelView *)wheel scrolledByDegrees:(CGFloat)degrees;
- (void)iPodWheelDidEndScrolling:(LTiPodWheelView *)wheel velocity:(CGFloat)degreesPerSecond;
@end

@interface LTiPodWheelView : UIView
@property (nonatomic, weak) id<LTiPodWheelDelegate> delegate;
@property (nonatomic, assign) BOOL showsPauseIcon; // play/pause button glyph state
@end

// ------------------------------------------------------------------ Main ----

@interface LTiPodViewController () <LTiPodWheelDelegate>
@property (nonatomic, strong) UIView *screenPanel;    // black plastic bezel around LCD
@property (nonatomic, strong) UIView *listHost;       // contains title bar + list/nowPlaying
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) LTiPodListView *listView;
@property (nonatomic, strong) LTiPodNowPlayingView *nowPlayingView;
@property (nonatomic, strong) LTiPodSearchView *searchView;
@property (nonatomic, strong) LTiPodWheelView *wheelView;

@property (nonatomic, strong) NSMutableArray *paneStack;   // of LTiPodPane
@property (nonatomic, strong) NSTimer *momentumTimer;
@property (nonatomic, assign) CGFloat momentumVelocity;

@property (nonatomic, assign) SystemSoundID scrollClickID;
@property (nonatomic, assign) BOOL scrollClickReady;
@property (nonatomic, assign) NSInteger lastClickRow;

@property (nonatomic, assign) SystemSoundID keyClickID;
@property (nonatomic, assign) BOOL keyClickReady;

@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, assign) BOOL showingNowPlaying;

@property (nonatomic, strong) NSTimer *volumeModeTimer;
@property (nonatomic, strong) NSMutableString *searchQuery;
@property (nonatomic, assign) NSInteger searchKeyIndex;
@property (nonatomic, assign) CGFloat searchKeyAccum;
@property (nonatomic, assign) BOOL searchYouTubeMode; // search YouTube instead of the library
@end

@implementation LTiPodViewController

#pragma mark - Enabling

+ (BOOL)isEnabled {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:LTiPodModeEnabledKey] == nil) return NO;
    return [ud boolForKey:LTiPodModeEnabledKey];
}

+ (void)setEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:LTiPodModeEnabledKey];
}

+ (void)applyiPodModeAnimated:(BOOL)animated {
    UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
    UIViewController *currentRoot = window.rootViewController;
    UIViewController *newRoot = [LTiPodViewController isEnabled] ? [[LTiPodViewController alloc] init] : nil;
    if ((currentRoot && [currentRoot isKindOfClass:[LTiPodViewController class]]) == ([newRoot isKindOfClass:[LTiPodViewController class]])) {
        if (!newRoot) newRoot = [[self class] makeStandardRoot];
        [LTAppDelegate applyDisplayModeAnimated:animated];
        return;
    }
    if (!newRoot) newRoot = [[self class] makeStandardRoot];

    // Capture the old screen so we can cross-fade (iOS 6 safe).
    UIView *oldView = currentRoot.view;
    UIGraphicsBeginImageContext(oldView.bounds.size);
    [oldView.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *snap = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    window.rootViewController = newRoot;
    [LTAppDelegate applyDisplayModeAnimated:NO];

    if (snap && animated) {
        UIImageView *overlay = [[UIImageView alloc] initWithImage:snap];
        overlay.frame = oldView.bounds;
        [window addSubview:overlay];
        [UIView animateWithDuration:0.35f
            animations:^{ overlay.alpha = 0.0f; }
            completion:^(BOOL finished) { [overlay removeFromSuperview]; }];
    }
}

+ (UIViewController *)standardRootViewController {
    // Rebuild the standard tab-bar root (kept in sync with LTAppDelegate).
    return [LTAppDelegate standardRootViewController];
}

// Root controller returned when iPod mode is OFF. Exposed via LTAppDelegate.
+ (UIViewController *)makeStandardRoot {
    return [LTAppDelegate standardRootViewController];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.edgesForExtendedLayout = UIRectEdgeNone;
    }
    // Continuous graphite housing behind the LCD and click wheel, so the wheel
    // square visually disappears into the body instead of reading as a box.
    self.view.backgroundColor = [UIColor colorWithWhite:0.18f alpha:1.0f];

    self.screenPanel = [[UIView alloc] initWithFrame:CGRectZero];
    self.screenPanel.backgroundColor = [UIColor colorWithWhite:0.09f alpha:1.0f];
    self.screenPanel.layer.cornerRadius = 10.0f;
    self.screenPanel.clipsToBounds = YES;
    [self.view addSubview:self.screenPanel];

    self.listHost = [[UIView alloc] initWithFrame:CGRectZero];
    self.listHost.backgroundColor = [UIColor whiteColor];
    [self.screenPanel addSubview:self.listHost];

    self.wheelView = [[LTiPodWheelView alloc] initWithFrame:CGRectZero];
    self.wheelView.delegate = self;
    [self.view addSubview:self.wheelView];

    [self buildTitleBarInHost];
    self.paneStack = [NSMutableArray array];
    [self pushRootPane];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(playerTrackChanged:) name:LTPlayerTrackDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(playerStateChanged:) name:LTPlayerStateDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(playerQueueChanged:) name:LTPlayerQueueDidChangeNotification object:nil];
}

- (void)updateWheelPlayState {
    LTPlayerController *player = [LTPlayerController sharedController];
    self.wheelView.showsPauseIcon = player.isPlaying;
    [self.wheelView setNeedsDisplay];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    [self updateWheelPlayState];
    [self refreshNowPlayingPane];
    [self startClock];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    [self stopClock];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.momentumTimer invalidate];
    [self.clockTimer invalidate];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat w = b.size.width;
    CGFloat h = b.size.height;

    // Keep the LCD and click wheel inside the safe area on notched devices
    // (the graphite housing background still fills the whole screen).
    CGFloat topInset = LTSafeAreaTop(self.view);
    CGFloat bottomInset = LTSafeAreaBottom(self.view);
    CGFloat usableH = h - topInset - bottomInset;
    if (usableH < 1.0f) usableH = h;

    CGFloat screenTop = topInset + roundf(usableH * 0.04f);
    CGFloat screenH = roundf(usableH * 0.33f);
    CGFloat screenX = roundf(w * 0.05f);
    CGFloat screenW = w - screenX * 2.0f;
    self.screenPanel.frame = CGRectMake(screenX, screenTop, screenW, screenH);
    self.listHost.frame = CGRectInset(self.screenPanel.bounds, 3.0f, 3.0f);

    CGFloat wheelD = roundf(usableH * 0.50f);
    CGFloat wheelY = screenTop + screenH + roundf(usableH * 0.03f);
    CGFloat wheelBottomLimit = h - bottomInset - roundf(usableH * 0.03f);
    if (wheelY + wheelD > wheelBottomLimit) {
        wheelD = wheelBottomLimit - wheelY;
    }
    if (wheelD < 1.0f) wheelD = 1.0f;
    self.wheelView.frame = CGRectMake(roundf((w - wheelD) / 2.0f), wheelY, wheelD, wheelD);
    LTLog(@"iPod wheel frame=%@", NSStringFromCGRect(self.wheelView.frame));

    [self layoutTitleBarInHost];
    [self layoutContent];
}

#pragma mark - Title bar (inside the LCD)

- (void)buildTitleBarInHost {
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.backgroundColor = [UIColor colorWithRed:0.13f green:0.32f blue:0.58f alpha:1.0f];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:12.0f];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.listHost addSubview:self.titleLabel];
}

- (void)layoutTitleBarInHost {
    CGRect host = self.listHost.bounds;
    self.titleLabel.frame = CGRectMake(0, 0, host.size.width, 20.0f);
}

- (void)setLCDTitle:(NSString *)title {
    self.titleLabel.text = title;
}

#pragma mark - Pane stack

- (void)pushRootPane {
    LTiPodPane *root = [self mainMenuPane];
    [self.paneStack addObject:root];
    [self presentPane:root];
}

- (LTiPodPane *)mainMenuPane {
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    pane.title = @"audioNINJA";
    NSMutableArray *items = [NSMutableArray array];

    LTPlayerController *player = [LTPlayerController sharedController];
    LTTrack *current = [player currentTrack];
    BOOL nowPlayingAvailable = current && [player.queue count] > 0;

    [items addObject:[LTiPodItem submenu:@"Music"]];

    LTiPodItem *shuffle = [[LTiPodItem alloc] initWithTitle:@"Shuffle Songs"
                                                    subtitle:nil
                                                     action:LTiPodActionShuffleAll];
    shuffle.faIcon = 0xF074; // shuffle
    [items addObject:shuffle];

    LTiPodItem *settings = [LTiPodItem submenu:@"Settings"];
    settings.faIcon = 0xF013; // gear
    [items addObject:settings];

    LTiPodItem *searchRow = [LTiPodItem submenu:@"Search"];
    searchRow.faIcon = 0xF002; // magnifying glass
    [items addObject:searchRow];

    // Now Playing only appears once there is an active track, at the bottom.
    if (nowPlayingAvailable) {
        LTiPodItem *np = [[LTiPodItem alloc] initWithTitle:@"Now Playing"
                                                  subtitle:[NSString stringWithFormat:@"%@ — %@",
                                                            current.artist.length ? current.artist : @"Unknown Artist",
                                                            current.title]
                                                    action:LTiPodActionNowPlaying];
        np.nowPlayingRow = YES;
        [items addObject:np];
    }
    pane.items = items;
    return pane;
}

- (LTiPodPane *)musicPane {
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    pane.title = @"Music";
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[LTiPodItem submenu:@"Playlists"]];
    [items addObject:[LTiPodItem submenu:@"Artists"]];
    [items addObject:[LTiPodItem submenu:@"Albums"]];
    [items addObject:[LTiPodItem submenu:@"Songs"]];
    pane.items = items;
    return pane;
}

- (LTiPodPane *)submenuPaneForItem:(LTiPodItem *)item {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    NSMutableArray *items = [NSMutableArray array];

    // Determine sub-name + aggregate into "playable" buckets.
    NSString *lower = item.title.lowercaseString;
    if ([lower isEqualToString:@"playlists"]) {
        pane.title = @"Playlists";
        for (LTLocalPlaylist *playlist in store.playlists) {
            LTiPodItem *row = [LTiPodItem submenu:playlist.name.length ? playlist.name : @"Untitled"];
            row.tracks = [NSArray arrayWithArray:playlist.tracks];
            row.subtitle = [NSString stringWithFormat:@"%d songs", (int)playlist.tracks.count];
            [items addObject:row];
        }
    } else if ([lower isEqualToString:@"artists"]) {
        pane.title = @"Artists";
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (LTTrack *t in store.libraryTracks) {
            NSString *name = t.artist.length ? t.artist : @"Unknown Artist";
            NSMutableArray *bucket = [map objectForKey:name];
            if (!bucket) {
                bucket = [NSMutableArray array];
                [map setObject:bucket forKey:name];
            }
            [bucket addObject:t];
        }
        for (NSString *name in [map allKeys]) {
            NSArray *list = [map objectForKey:name];
            LTiPodItem *row = [LTiPodItem submenu:name];
            row.tracks = list;
            row.subtitle = [NSString stringWithFormat:@"%d songs", (int)list.count];
            [items addObject:row];
        }
    } else if ([lower isEqualToString:@"albums"]) {
        pane.title = @"Albums";
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (LTTrack *t in store.libraryTracks) {
            NSString *album = t.album.length ? t.album : @"Unknown Album";
            NSString *artist = t.artist.length ? t.artist : @"Unknown Artist";
            NSString *key = [NSString stringWithFormat:@"%@|%@", album.lowercaseString, artist.lowercaseString];
            NSMutableDictionary *bucket = [map objectForKey:key];
            if (!bucket) {
                bucket = [NSMutableDictionary dictionaryWithObjectsAndKeys:album, @"name",
                                                                   artist, @"artist", nil];
                [map setObject:bucket forKey:key];
            }
            NSMutableArray *tracks = [bucket objectForKey:@"tracks"];
            if (!tracks) {
                tracks = [NSMutableArray array];
                [bucket setObject:tracks forKey:@"tracks"];
            }
            [tracks addObject:t];
        }
        for (NSDictionary *bucket in [map allValues]) {
            NSArray *list = [bucket objectForKey:@"tracks"];
            LTiPodItem *row = [LTiPodItem submenu:[bucket objectForKey:@"name"]];
            row.subtitle = [bucket objectForKey:@"artist"];
            row.tracks = list;
            [items addObject:row];
        }
    } else if ([lower isEqualToString:@"songs"]) {
        pane.title = @"All Songs";
        NSArray *tracks = store.libraryTracks;
        for (NSInteger i = 0; i < (NSInteger)tracks.count; i++) {
            LTTrack *track = [tracks objectAtIndex:(NSUInteger)i];
            [items addObject:[LTiPodItem playItemForTrack:track tracks:tracks index:i]];
        }
    } else if (item.tracks.count > 0) {
        // Direct song bucket (playlist / artist / album).
        pane.title = item.title;
        NSArray *tracks = item.tracks;
        for (NSInteger i = 0; i < (NSInteger)tracks.count; i++) {
            LTTrack *track = [tracks objectAtIndex:(NSUInteger)i];
            [items addObject:[LTiPodItem playItemForTrack:track tracks:tracks index:i]];
        }
    } else {
        pane.title = item.title;
    }
    pane.items = items;
    return pane;
}

- (LTiPodPane *)settingsPane {
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    pane.title = @"Settings";
    NSMutableArray *items = [NSMutableArray array];

    LTiPodItem *about = [LTiPodItem submenu:@"About"];
    about.subtitle = [self appVersion] ?: @"";
    [items addObject:about];

    LTiPodItem *vibes = [[LTiPodItem alloc] initWithTitle:@"Vibrations"
                                                 subtitle:[self vibesEnabled] ? @"On" : @"Off"
                                                  action:LTiPodActionToggleVibrations];
    [items addObject:vibes];

    LTiPodItem *clicks = [[LTiPodItem alloc] initWithTitle:@"Click Sound"
                                                  subtitle:[self clickSoundEnabled] ? @"On" : @"Off"
                                                   action:LTiPodActionToggleClickSound];
    [items addObject:clicks];

    LTiPodItem *exit = [[LTiPodItem alloc] initWithTitle:@"Exit iPod Mode"
                                                 subtitle:nil
                                                  action:LTiPodActionExit];
    [items addObject:exit];

    pane.items = items;
    return pane;
}

- (LTiPodPane *)aboutPane {
    NSString *version = [self appVersion] ?: @"0.1.0";
    NSString *detail = [NSString stringWithFormat:@"Version %@", version];
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    pane.title = @"About";
    pane.isInfo = YES;
    NSMutableArray *items = [NSMutableArray array];
    NSArray *lines = @[@"audioNINJA Legacy",
                       detail,
                       @"iPod mode emulator",
                       @"For legacy iOS devices",
                       @"by SuperYosh23"];
    for (NSString *line in lines) {
        [items addObject:[[LTiPodItem alloc] initWithTitle:line subtitle:nil action:LTiPodActionNone]];
    }
    pane.items = items;
    return pane;
}

- (NSString *)appVersion {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}

#pragma mark - Presenting panes

- (void)presentPane:(LTiPodPane *)pane {
    [self setLCDTitle:pane.title];
    [self stopClock];
    self.showingNowPlaying = NO;
    self.nowPlayingView.volumeMode = NO;
    [self.volumeModeTimer invalidate];
    self.volumeModeTimer = nil;

    self.nowPlayingView.hidden = YES;
    self.listView.hidden = NO;
    self.searchView.hidden = YES;

    if (!self.listView) {
        self.listView = [[LTiPodListView alloc] initWithFrame:CGRectZero];
        [self.listHost addSubview:self.listView];
    }
    self.listView.items = pane.items;
    self.listView.contentOffset = 0.0f;
    self.listView.showsChevrons = YES;

    // Titles with submenus get a trailing chevron; plain songs don't.
    BOOL songsOnly = YES;
    for (LTiPodItem *item in pane.items) {
        if (item.action != LTiPodActionPlay) { songsOnly = NO; break; }
    }
    self.listView.showsChevrons = !songsOnly && !pane.isInfo;
    [self layoutContent];
}

- (void)presentSearchScreen {
    [self setLCDTitle:self.searchYouTubeMode ? @"YouTube" : @"Library"];
    [self stopClock];
    self.showingNowPlaying = NO;
    self.nowPlayingView.volumeMode = NO;
    [self.volumeModeTimer invalidate];
    self.volumeModeTimer = nil;

    self.listView.hidden = YES;
    self.nowPlayingView.hidden = YES;
    if (!self.searchView) {
        self.searchView = [[LTiPodSearchView alloc] initWithFrame:CGRectZero];
        self.searchView.backgroundColor = [UIColor whiteColor];
        [self.listHost addSubview:self.searchView];
    }
    if (!self.searchQuery) self.searchQuery = [NSMutableString string];
    self.searchView.hidden = NO;
    [self refreshSearchView];
    [self layoutContent];
}

- (void)refreshSearchView {
    if (!self.searchView) return;
    self.searchView.query = self.searchQuery;
    self.searchView.keyIndex = self.searchKeyIndex;
    self.searchView.results = [self resultsForQuery:self.searchQuery];
    [self.searchView setNeedsDisplay];
}

- (NSArray *)resultsForQuery:(NSString *)query {
    if (!query.length) return nil;
    NSArray *all = [[LTPlaylistStore sharedStore] libraryTracks];
    NSMutableArray *res = [NSMutableArray array];
    for (LTTrack *track in all) {
        NSString *title = track.title.length ? track.title : @"";
        NSString *artist = track.artist.length ? track.artist : @"";
        if ([title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [artist rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [res addObject:track];
        }
    }
    return res;
}

- (void)advanceSearchKeyByDegrees:(CGFloat)degrees {
    NSUInteger total = LTiPodSearchKeyCount();
    const CGFloat step = 12.0f; // degrees per key
    self.searchKeyAccum += degrees;
    NSInteger advance = (NSInteger)floorf(self.searchKeyAccum / step);
    self.searchKeyAccum -= (CGFloat)advance * step;
    NSInteger idx = self.searchKeyIndex + advance;
    if (idx < 0) idx = 0;
    if (idx > (NSInteger)total - 1) idx = (NSInteger)total - 1;
    if (idx != self.searchKeyIndex) {
        self.searchKeyIndex = idx;
        [self playScrollClickForOffset:(CGFloat)idx * [LTiPodListView rowHeight]];
        [self refreshSearchView];
    }
}

- (void)performSearchKeyAction {
    [self playKeyClick];
    NSInteger act = LTiPodSearchKeyAction((NSUInteger)self.searchKeyIndex);
    if (act == 0) { // letter
        if (self.searchQuery.length >= 40) return;
        [self.searchQuery appendString:LTiPodSearchKeyLabel((NSUInteger)self.searchKeyIndex)];
        [self refreshSearchView];
    } else if (act == 1) { // backspace
        if (self.searchQuery.length) {
            [self.searchQuery deleteCharactersInRange:NSMakeRange(self.searchQuery.length - 1, 1)];
        }
        [self refreshSearchView];
    } else if (act == 2) { // space
        if (self.searchQuery.length >= 40) return;
        [self.searchQuery appendString:@" "];
        [self refreshSearchView];
    } else if (act == 3) { // clear
        [self.searchQuery setString:@""];
        [self refreshSearchView];
    } else if (act == 4) { // go
        if (self.searchYouTubeMode) {
            [self performYouTubeSearch];
        } else {
            NSArray *matches = [self resultsForQuery:self.searchQuery];
            if (matches.count) [self pushPane:[self searchResultsPane:matches]];
        }
    }
}

- (void)performYouTubeSearch {
    NSString *query = [self.searchQuery stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!query.length) return;
    self.searchView.loading = YES;
    [self.searchView setNeedsDisplay];
    __weak LTiPodViewController *weakSelf = self;
    // Same as the "Songs" tab in the main interface (YouTube Music search).
    [[LTYouTubeClient sharedClient] searchWithQuery:query type:@"songs" completion:^(NSArray *tracks, NSError *error) {
        LTiPodViewController *strongSelf = weakSelf;
        strongSelf.searchView.loading = NO;
        [strongSelf.searchView setNeedsDisplay];
        if (!strongSelf || !strongSelf.searchActive) return;
        NSArray *matches = tracks ?: [NSArray array];
        if (error || !matches.count) return;
        [strongSelf pushPane:[strongSelf searchResultsPane:matches]];
    }];
}

- (LTiPodPane *)searchResultsPane:(NSArray *)matches {
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    pane.title = [NSString stringWithFormat:@"%d Results", (int)matches.count];
    NSMutableArray *items = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)matches.count; i++) {
        LTTrack *track = [matches objectAtIndex:(NSUInteger)i];
        [items addObject:[LTiPodItem playItemForTrack:track tracks:matches index:i]];
    }
    pane.items = items;
    return pane;
}

- (void)presentNowPlayingScreen {
    [self setLCDTitle:@"Now Playing"];
    [self stopClock];
    self.showingNowPlaying = YES;

    self.listView.hidden = YES;
    self.searchView.hidden = YES;
    if (!self.nowPlayingView) {
        self.nowPlayingView = [[LTiPodNowPlayingView alloc] initWithFrame:CGRectZero];
        self.nowPlayingView.backgroundColor = [UIColor whiteColor];
        [self.listHost addSubview:self.nowPlayingView];
    }
    self.nowPlayingView.hidden = NO;
    [self refreshNowPlayingPane];
    [self layoutContent];
    [self startClock];
}

- (void)layoutContent {
    CGRect host = self.listHost.bounds;
    CGFloat top = 20.0f; // below the title bar
    CGRect content = CGRectMake(0, top, host.size.width, host.size.height - top);
    self.listView.frame = content;
    self.nowPlayingView.frame = content;
    self.searchView.frame = content;
}

#pragma mark - Actions

- (void)handleSelectOnPane:(LTiPodPane *)pane {
    LTiPodItem *item = [self selectedItemInPane:pane];
    if (!item) return;
    switch (item.action) {
        case LTiPodActionSubmenu: {
            if ([item.title isEqualToString:@"Music"] && !item.tracks.count) {
                [self pushPane:[self musicPane]];
                return;
            }
            if ([item.title isEqualToString:@"Settings"]) {
                [self pushPane:[self settingsPane]];
                return;
            }
            if ([item.title isEqualToString:@"Now Playing"]) {
                [self pushPane:[self nowPlayingPane]];
                return;
            }
            if ([item.title isEqualToString:@"About"] && !item.tracks.count) {
                [self pushPane:[self aboutPane]];
                return;
            }
            if ([item.title isEqualToString:@"Search"]) {
                [self pushPane:[self searchPickerPane]];
                return;
            }
            [self pushPane:[self submenuPaneForItem:item]];
            break;
        }
        case LTiPodActionNowPlaying:
            [self pushPane:[self nowPlayingPane]];
            break;
        case LTiPodActionSearchLibrary:
            self.searchYouTubeMode = NO;
            self.searchQuery = [NSMutableString string];
            self.searchKeyIndex = 0;
            self.searchKeyAccum = 0.0f;
            [self pushPane:[self searchPane]];
            break;
        case LTiPodActionSearchYouTube:
            self.searchYouTubeMode = YES;
            self.searchQuery = [NSMutableString string];
            self.searchKeyIndex = 0;
            self.searchKeyAccum = 0.0f;
            [self pushPane:[self searchPane]];
            break;
        case LTiPodActionToggleVibrations:
            [self setVibesEnabled:![self vibesEnabled]];
            item.subtitle = [self vibesEnabled] ? @"On" : @"Off";
            [self.listView setNeedsDisplay];
            break;
        case LTiPodActionToggleClickSound:
            [self setClickSoundEnabled:![self clickSoundEnabled]];
            item.subtitle = [self clickSoundEnabled] ? @"On" : @"Off";
            [self.listView setNeedsDisplay];
            break;
        case LTiPodActionPlay: {
            LTPlayerController *player = [LTPlayerController sharedController];
            if (!item.tracks.count) break;
            player.queueSourceName = @"iPod";
            [player playQueue:item.tracks atIndex:item.playIndex];
            [self pushPane:[self nowPlayingPane]];
            break;
        }
        case LTiPodActionShuffleAll: {
            LTPlaylistStore *store = [LTPlaylistStore sharedStore];
            LTPlayerController *player = [LTPlayerController sharedController];
            player.queueSourceName = @"iPod Shuffle";
            [player playQueue:store.libraryTracks shuffle:YES];
            [self pushPane:[self nowPlayingPane]];
            break;
        }
        case LTiPodActionExit:
            [LTiPodViewController setEnabled:NO];
            [LTiPodViewController applyiPodModeAnimated:YES];
            break;
        case LTiPodActionNone:
        default:
            break;
    }
}

- (LTiPodPane *)nowPlayingPane {
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    pane.title = @"Now Playing";
    pane.isNowPlaying = YES;
    return pane;
}

- (LTiPodPane *)searchPane {
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    pane.title = @"Search";
    pane.isSearch = YES;
    return pane;
}

- (LTiPodPane *)searchPickerPane {
    LTiPodPane *pane = [[LTiPodPane alloc] init];
    pane.title = @"Search";
    NSMutableArray *items = [NSMutableArray array];
    LTiPodItem *lib = [[LTiPodItem alloc] initWithTitle:@"Library"
                                               subtitle:nil
                                                action:LTiPodActionSearchLibrary];
    lib.faIcon = 0xF02D; // book
    [items addObject:lib];
    LTiPodItem *yt = [[LTiPodItem alloc] initWithTitle:@"YouTube"
                                              subtitle:nil
                                               action:LTiPodActionSearchYouTube];
    yt.faIcon = 0xF144; // play-circle
    [items addObject:yt];
    pane.items = items;
    return pane;
}

- (BOOL)searchActive {
    return ((LTiPodPane *)[self.paneStack lastObject]).isSearch;
}

- (void)pushPane:(LTiPodPane *)pane {
    [self.paneStack addObject:pane];
    if (pane.isNowPlaying) {
        [self presentNowPlayingScreen];
    } else if (pane.isSearch) {
        [self presentSearchScreen];
    } else {
        [self presentPane:pane];
    }
}

- (void)popPane {
    if (self.paneStack.count <= 1) return;
    [self.paneStack removeLastObject];
    LTiPodPane *pane = [self.paneStack lastObject];
    if (pane.isNowPlaying) {
        [self presentNowPlayingScreen];
    } else if (pane.isSearch) {
        [self presentSearchScreen];
    } else {
        [self presentPane:pane];
    }
    if (self.paneStack.count == 1) [self refreshMainMenuTile];
}

- (LTiPodItem *)selectedItemInPane:(LTiPodPane *)pane {
    NSInteger index = self.listView.selectedIndex;
    if (index < 0 || index >= (NSInteger)pane.items.count) return nil;
    return [pane.items objectAtIndex:(NSUInteger)index];
}

- (void)scrollListByDegrees:(CGFloat)degrees {
    // On the now-playing screen the wheel is a volume knob, not a list scroll.
    if (self.showingNowPlaying) {
        [self adjustVolumeByDegrees:degrees];
        return;
    }
    if ([self searchActive]) {
        [self advanceSearchKeyByDegrees:degrees];
        return;
    }
    if (!self.listView || self.listView.hidden) return;
    [self stopMomentum];
    CGFloat rowH = [LTiPodListView rowHeight];
    CGFloat delta = degrees / 18.0f * rowH; // 18° per row feels closest to real
    if (fabs(delta) < 0.5f) return;
    CGFloat target = self.listView.contentOffset + delta;
    CGFloat max = [self maxContentOffset];
    if (target < 0) target = 0;
    if (target > max) target = max;
    LTLog(@"iPod scroll deg=%.1f target=%.1f max=%.1f items=%d", degrees, target, max, (int)self.listView.items.count);
    [self.listView setContentOffsetImmediate:target];
    [self playScrollClickForOffset:self.listView.contentOffset];
}

- (void)adjustVolumeByDegrees:(CGFloat)degrees {
    // Adjust our own audio output instead of MPMusicPlayerController: the
    // latter synchronously talks to MediaRemote/RemotePlayerService on the
    // main thread and deadlocks (watchdog 0x8badf00d) on iOS 12.
    LTPlayerController *player = [LTPlayerController sharedController];
    float v = player.volume;
    v += degrees / 18.0f * 0.05f; // a 360° spin sweeps ~1 volume
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    player.volume = v;
    self.nowPlayingView.volume = v;
    self.nowPlayingView.volumeMode = YES;
    [self.nowPlayingView setNeedsDisplay];

    [self.volumeModeTimer invalidate];
    __weak LTiPodViewController *weakSelf = self;
    self.volumeModeTimer = [NSTimer scheduledTimerWithTimeInterval:0.9f
                                                            target:weakSelf
                                                          selector:@selector(volumeModeExpired:)
                                                          userInfo:nil
                                                           repeats:NO];
}

- (void)volumeModeExpired:(NSTimer *)timer {
    self.volumeModeTimer = nil;
    self.nowPlayingView.volumeMode = NO;
    [self.nowPlayingView setNeedsDisplay];
}

- (void)stopMomentum {
    [self.momentumTimer invalidate];
    self.momentumTimer = nil;
}

- (void)prepareScrollClick {
    if (self.scrollClickReady) return;
    self.scrollClickReady = YES;
    self.lastClickRow = NSIntegerMax;
    if (self.scrollClickID) {
        AudioServicesRemoveSystemSoundCompletion(self.scrollClickID);
        AudioServicesDisposeSystemSoundID(self.scrollClickID);
        self.scrollClickID = 0;
    }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"scrollclick.wav"];
    LTWriteToneWAV(path, 2400.0, 0.65, 3300.0, 0.35, 90.0, 0.045);
    if (AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:path], &_scrollClickID) == kAudioServicesNoError) {
        AudioServicesPlaySystemSound(self.scrollClickID); // warm up lazy audio stack
    }
}

- (void)prepareKeyClick {
    if (self.keyClickReady) return;
    self.keyClickReady = YES;
    if (self.keyClickID) {
        AudioServicesRemoveSystemSoundCompletion(self.keyClickID);
        AudioServicesDisposeSystemSoundID(self.keyClickID);
        self.keyClickID = 0;
    }
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"keyclick.wav"];
    LTWriteToneWAV(path, 720.0, 0.7, 1440.0, 0.3, 55.0, 0.055); // soft keyboard "tock"
    if (AudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:path], &_keyClickID) == kAudioServicesNoError) {
        AudioServicesPlaySystemSound(self.keyClickID);
    }
}

- (void)playKeyClick {
    if (!self.keyClickReady) [self prepareKeyClick];
    if (!self.keyClickID) return;
    AudioServicesPlaySystemSound(self.keyClickID);
}

#pragma mark - Wheel feedback preferences

- (BOOL)vibesEnabled {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:@"LTiPodVibrationsEnabled"] == nil) return YES;
    return [ud boolForKey:@"LTiPodVibrationsEnabled"];
}

- (void)setVibesEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"LTiPodVibrationsEnabled"];
}

- (BOOL)clickSoundEnabled {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:@"LTiPodClickSoundEnabled"] == nil) return YES;
    return [ud boolForKey:@"LTiPodClickSoundEnabled"];
}

- (void)setClickSoundEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"LTiPodClickSoundEnabled"];
}

- (void)playScrollClickForOffset:(CGFloat)offset {
    if (!self.scrollClickReady) [self prepareScrollClick];
    if (!self.scrollClickID) return;
    // The on-screen highlight row is floor(contentOffset / rowHeight) — see
    // LTiPodListView.selectedIndex. Fire feedback only when that row changes,
    // so effects never precede the visible indicator.
    NSInteger row = (NSInteger)floorf(offset / [LTiPodListView rowHeight]);
    if (row < 0) row = 0;
    if (row == self.lastClickRow) return;
    self.lastClickRow = row;
    if ([self clickSoundEnabled]) AudioServicesPlaySystemSound(self.scrollClickID);
    if ([self vibesEnabled]) [self playScrollHaptic];
}

// Short tactile pulse: buzz the plain motor for a split second (AudioServices
// has no public way to time the motor, but the long-standing private helper
// AudioServicesPlaySystemSoundWithVibration does; resolve it at runtime since
// it is not in the SDK's link stub).
- (void)playScrollHaptic {
    static void (*vibeFn)(SystemSoundID, void *, NSDictionary *) = NULL;
    static BOOL resolved = NO;
    if (!resolved) {
        vibeFn = dlsym(RTLD_DEFAULT, "AudioServicesPlaySystemSoundWithVibration");
        resolved = YES;
    }
    if (!vibeFn) return;
    NSMutableDictionary *vibe = [NSMutableDictionary dictionary];
    [vibe setObject:[NSArray arrayWithObjects:
                     [NSNumber numberWithBool:NO], [NSNumber numberWithInt:0],
                     [NSNumber numberWithBool:YES], [NSNumber numberWithInt:10], nil]
             forKey:@"VibePattern"];
    [vibe setObject:[NSNumber numberWithInt:1] forKey:@"Intensity"];
    vibeFn(kSystemSoundID_Vibrate, NULL, vibe); // ~10ms motor pulse
}

- (CGFloat)maxContentOffset {
    NSArray *items = self.listView.items;
    if (items.count <= 1) return 0;
    return ((CGFloat)(items.count - 1)) * [LTiPodListView rowHeight];
}

#pragma mark - Momentum

- (void)startMomentumWithVelocity:(CGFloat)degreesPerSecond {
    if (fabs(degreesPerSecond) < 40.0f) {
        [self.listView snapSelection];
        return;
    }
    if (self.momentumTimer) [self.momentumTimer invalidate];
    CGFloat rowH = [LTiPodListView rowHeight];
    CGFloat v = degreesPerSecond / 18.0f * rowH * 0.35f; // scaled glide
    if (v > 420.0f) v = 420.0f;
    if (v < -420.0f) v = -420.0f;
    self.momentumVelocity = v;
    __weak LTiPodViewController *weakSelf = self;
    self.momentumTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f / 30.0f
                                                          target:weakSelf
                                                        selector:@selector(momentumTick:)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)momentumTick:(NSTimer *)timer {
    if (!self.listView || self.listView.hidden) {
        [self.momentumTimer invalidate];
        self.momentumTimer = nil;
        return;
    }
    self.momentumVelocity *= 0.90f;
    CGFloat maxOffset = [self maxContentOffset];
    CGFloat target = self.listView.contentOffset + self.momentumVelocity / 30.0f;
    if (target < 0) { target = 0; self.momentumVelocity = -self.momentumVelocity * 0.3f; }
    else if (target > maxOffset) { target = maxOffset; self.momentumVelocity = -self.momentumVelocity * 0.3f; }
    [self.listView setContentOffsetImmediate:target];
    [self playScrollClickForOffset:self.listView.contentOffset];

    if (fabs(self.momentumVelocity) < 6.0f) {
        [self.momentumTimer invalidate];
        self.momentumTimer = nil;
        [self.listView snapSelection];
    }
}

#pragma mark - Now Playing refresh

- (void)refreshNowPlayingPane {
    LTiPodPane *top = [self.paneStack lastObject];
    if (!top.isNowPlaying) return;
    LTPlayerController *player = [LTPlayerController sharedController];
    LTTrack *track = [player currentTrack];
    if (!track) {
        self.nowPlayingView.track = nil;
        return;
    }
    self.nowPlayingView.track = track;
    self.nowPlayingView.isPlaying = player.isPlaying;
    self.nowPlayingView.elapsed = player.currentTime;
    self.nowPlayingView.total = player.duration > 0 ? player.duration : track.duration;
    [self loadArtworkForTrack:track];

    if (player.isPlaying) [self startClock];
    else [self stopClock];
}

- (void)loadArtworkForTrack:(LTTrack *)track {
    NSString *urlString = track.thumbnailURL.length ? [[LTYouTubeClient sharedClient] highResThumbnailURL:track.thumbnailURL] : nil;
    if (!urlString.length) {
        self.nowPlayingView.artImage = nil;
        [self.nowPlayingView setNeedsDisplay];
        return;
    }
    // Go through the shared client so iPod art uses the same disk cache and
    // letterbox-stripping crop as every other artwork surface in the app.
    __weak LTiPodViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:urlString completion:^(UIImage *image) {
        LTiPodViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (![strongSelf.nowPlayingView.track.videoId isEqualToString:track.videoId]) return;
        strongSelf.nowPlayingView.artImage = image;
        [strongSelf.nowPlayingView setNeedsDisplay];
    }];
}

- (void)clockTick:(NSTimer *)timer {
    if (!self.showingNowPlaying) return;
    LTPlayerController *player = [LTPlayerController sharedController];
    if (!player.isPlaying) return;
    self.nowPlayingView.elapsed = player.currentTime;
    self.nowPlayingView.total = player.duration > 0 ? player.duration : self.nowPlayingView.track.duration;
    [self.nowPlayingView setNeedsDisplay];
}

- (void)startClock {
    if (self.clockTimer) return;
    __weak LTiPodViewController *weakSelf = self;
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:0.5f target:weakSelf
                                                     selector:@selector(clockTick:) userInfo:nil repeats:YES];
}

- (void)stopClock {
    [self.clockTimer invalidate];
    self.clockTimer = nil;
}

#pragma mark - Player notifications

- (void)playerTrackChanged:(NSNotification *)note {
    [self refreshNowPlayingPane];
    [self refreshMainMenuTile];
    [self updateWheelPlayState];
}

- (void)playerStateChanged:(NSNotification *)note {
    [self refreshNowPlayingPane];
    [self updateWheelPlayState];
}

- (void)playerQueueChanged:(NSNotification *)note {
    [self refreshMainMenuTile];
}

- (void)refreshMainMenuTile {
    if (self.paneStack.count != 1) return;
    LTiPodPane *root = [self.paneStack lastObject];
    LTPlayerController *player = [LTPlayerController sharedController];
    LTTrack *current = [player currentTrack];
    BOOL available = current && player.queue.count > 0;
    BOOL rowExists = NO;
    for (LTiPodItem *item in root.items) {
        if (item.action == LTiPodActionNowPlaying) { rowExists = YES; break; }
    }
    if (available != rowExists) {
        // The Now Playing row appeared/disappeared: rebuild the menu.
        [self.paneStack replaceObjectAtIndex:0 withObject:[self mainMenuPane]];
        [self presentPane:[self.paneStack lastObject]];
        return;
    }
    for (LTiPodItem *item in root.items) {
        if (item.action != LTiPodActionNowPlaying) continue;
        if (available) {
            item.subtitle = [NSString stringWithFormat:@"%@ — %@",
                             current.artist.length ? current.artist : @"Unknown Artist",
                             current.title];
        } else {
            item.subtitle = nil;
        }
    }
    [self.listView setNeedsDisplay];
}

#pragma mark - LTiPodWheelDelegate

- (void)iPodWheel:(LTiPodWheelView *)wheel buttonPressed:(LTiPodWheelButton)button {
    [self stopMomentum];
    if ([self vibesEnabled]) [self playScrollHaptic]; // same short pulse as scrolling
    switch (button) {
        case LTiPodWheelButtonMenu:
            [self popPane];
            break;
        case LTiPodWheelButtonPrevious: {
            LTPlayerController *player = [LTPlayerController sharedController];
            if (player.queue.count) [player previousTrack];
            break;
        }
        case LTiPodWheelButtonPlayPause: {
            LTPlayerController *player = [LTPlayerController sharedController];
            if (!player.queue.count) [self playFirstLibraryTrack];
            else [player togglePlayPause];
            break;
        }
        case LTiPodWheelButtonNext: {
            LTPlayerController *player = [LTPlayerController sharedController];
            if (player.queue.count) [player nextTrack];
            break;
        }
        case LTiPodWheelButtonSelect: {
            LTiPodPane *top = [self.paneStack lastObject];
            if (top.isSearch) {
                [self performSearchKeyAction];
            } else if (top.isNowPlaying) {
                LTPlayerController *player = [LTPlayerController sharedController];
                if (!player.queue.count) {
                    [self playFirstLibraryTrack];
                } else {
                    [player togglePlayPause];
                }
                [self refreshNowPlayingPane];
            } else {
                [self handleSelectOnPane:top];
            }
            break;
        }
        default:
            break;
    }
}

- (void)playFirstLibraryTrack {
    LTPlaylistStore *store = [LTPlaylistStore sharedStore];
    NSArray *tracks = store.libraryTracks;
    if (!tracks.count) return;
    [LTPlayerController sharedController].queueSourceName = @"iPod";
    [[LTPlayerController sharedController] playQueue:tracks atIndex:0];
    [self refreshNowPlayingPane];
}

- (void)iPodWheel:(LTiPodWheelView *)wheel scrolledByDegrees:(CGFloat)degrees {
    [self scrollListByDegrees:degrees];
}

- (void)iPodWheelDidEndScrolling:(LTiPodWheelView *)wheel velocity:(CGFloat)degreesPerSecond {
    if (self.showingNowPlaying || [self searchActive]) return; // no glide for volume/search
    [self startMomentumWithVelocity:degreesPerSecond];
}

@end

// ------------------------------------------------------------- List view ----

@implementation LTiPodListView

+ (CGFloat)rowHeight { return 24.0f; }
+ (NSInteger)visibleRows { return 4; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor whiteColor];
        self.opaque = YES;
        _contentOffset = 0.0f;
        _showsChevrons = YES;
    }
    return self;
}

- (NSInteger)selectedIndex {
    NSInteger count = (NSInteger)_items.count;
    if (count <= 0) return 0;
    NSInteger index = (NSInteger)floorf(_contentOffset / [LTiPodListView rowHeight]);
    if (index < 0) index = 0;
    if (index > count - 1) index = count - 1;
    return index;
}

- (CGFloat)maxOffset {
    NSInteger count = (NSInteger)_items.count;
    if (count <= 1) return 0;
    return ((CGFloat)(count - 1)) * [LTiPodListView rowHeight];
}

- (CGFloat)maxScrollOffset {
    NSInteger count = (NSInteger)_items.count;
    if (count <= [LTiPodListView visibleRows]) return 0;
    return ((CGFloat)(count - [LTiPodListView visibleRows])) * [LTiPodListView rowHeight];
}

- (void)setContentOffsetImmediate:(CGFloat)offset {
    CGFloat clamped = offset < 0 ? 0 : (offset > [self maxOffset] ? [self maxOffset] : offset);
    _contentOffset = clamped;
    [self setNeedsDisplay];
}

- (void)setContentOffset:(CGFloat)contentOffset {
    [self setContentOffsetImmediate:contentOffset];
}

- (void)snapSelection {
    CGFloat rowH = [LTiPodListView rowHeight];
    CGFloat snapped = roundf(_contentOffset / rowH) * rowH;
    [self setContentOffsetImmediate:snapped];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat rowH = [LTiPodListView rowHeight];
    NSInteger count = (NSInteger)_items.count;
    if (count <= 0) return;

    NSInteger selected = self.selectedIndex;
    CGFloat drawOffset = _contentOffset;
    CGFloat maxScroll = [self maxScrollOffset];
    if (drawOffset > maxScroll) drawOffset = maxScroll;

    // Highlight bar: pinned to the top row on scrolling lists, but glides down
    // like a cursor when all rows already fit on the LCD.
    CGFloat barY = (CGFloat)selected * rowH - drawOffset;
    if (barY < 0) barY = 0;
    if (barY > bounds.size.height - rowH) barY = bounds.size.height - rowH;
    CGContextSaveGState(ctx);
    CGContextAddRect(ctx, CGRectMake(0, barY, bounds.size.width, rowH));
    CGContextClip(ctx);
    CGFloat colors[8] = {
        0.42f, 0.62f, 0.95f, 1.0f,
        0.12f, 0.34f, 0.80f, 1.0f,
    };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, NULL, 2);
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, barY), CGPointMake(0, barY + rowH), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(ctx);

    // Rows.
    CGFloat w = bounds.size.width;
    for (NSInteger i = 0; i < count; i++) {
        CGFloat itemY = (CGFloat)i * rowH - drawOffset;
        if (itemY + rowH < 0 || itemY > bounds.size.height) continue;
        LTiPodItem *item = [_items objectAtIndex:(NSUInteger)i];
        // The selected row is the one at the top of the LCD: floor(offset/rowH).
        // It always sits under the highlight bar, even mid-scroll.
        BOOL highlighted = (i == selected);

        UIColor *textColor = highlighted ? [UIColor whiteColor] : [UIColor blackColor];
        UIColor *dimColor  = highlighted ? [UIColor colorWithWhite:0.8f alpha:1.0f]
                                         : [UIColor colorWithWhite:0.35f alpha:1.0f];

        CGFloat x = 4.0f;
        CGContextSaveGState(ctx);
        [textColor set];
        [self drawLeftIconForItem:item inRect:CGRectMake(x, itemY + 3.0f, 14.0f, 14.0f)];
        CGContextRestoreGState(ctx);
        x += 18.0f;

        UIFont *font = [UIFont boldSystemFontOfSize:11.0f];
        [textColor set];
        [item.title drawAtPoint:CGPointMake(x, itemY + 5.0f) withFont:font];

        CGFloat right = w - (_showsChevrons ? 14.0f : 4.0f);
        if (item.subtitle.length && highlighted) {
            UIFont *small = [UIFont systemFontOfSize:9.0f];
            float sw = [item.subtitle sizeWithFont:small].width;
            if (sw + x < right - 4.0f) {
                [dimColor set];
                [item.subtitle drawAtPoint:CGPointMake(right - sw, itemY + 8.0f) withFont:small];
            }
        }

        if (_showsChevrons) {
            [dimColor set];
            UIFont *fa = LTiPodFAFont(11.0f);
            if (fa) {
                NSString *s = [NSString stringWithFormat:@"%C", (unichar)0xF0DA]; // fa-caret-right
                CGSize sz = [s sizeWithFont:fa];
                [s drawAtPoint:CGPointMake(w - sz.width - 2.0f, itemY + (rowH - sz.height) / 2.0f) withFont:fa];
            } else {
                [@"»" drawAtPoint:CGPointMake(w - 14.0f, itemY + 5.0f)
                         withFont:[UIFont boldSystemFontOfSize:11.0f]];
            }
        }
    }
}

- (void)drawLeftIconForItem:(LTiPodItem *)item inRect:(CGRect)rect {
    UIFont *fa = LTiPodFAFont(12.0f);
    if (fa) {
        unichar ch = item.nowPlayingRow ? (unichar)0xF04B : item.faIcon; // play / per-item
        if (!ch) ch = (unichar)0xF001;
        NSString *s = [NSString stringWithFormat:@"%C", ch];
        CGSize sz = [s sizeWithFont:fa];
        [s drawAtPoint:CGPointMake(rect.origin.x + (rect.size.width - sz.width) / 2.0f - 1.0f,
                                   rect.origin.y + (rect.size.height - sz.height) / 2.0f)
               withFont:fa];
        return;
    }
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat x = rect.origin.x + 3.0f;
    CGFloat y = rect.origin.y + 9.0f;
    if (item.nowPlayingRow) {
        CGFloat yy = rect.origin.y + rect.size.height / 2.0f;
        CGContextMoveToPoint(ctx, rect.origin.x + 1.0f, yy - 5.0f);
        CGContextAddLineToPoint(ctx, rect.origin.x + 6.0f, yy - 1.0f);
        CGContextAddLineToPoint(ctx, rect.origin.x + 1.0f, yy + 4.0f);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);
        return;
    }
    CGContextSetLineWidth(ctx, 1.0f);
    CGContextFillEllipseInRect(ctx, CGRectMake(x, y - 1.5f, 3.0f, 3.0f));
    CGContextFillEllipseInRect(ctx, CGRectMake(x + 5.0f, y - 1.5f, 3.0f, 3.0f));
    CGContextMoveToPoint(ctx, x + 3.5f, y + 1.0f);
    CGContextAddLineToPoint(ctx, x + 3.5f, y - 8.0f);
    CGContextAddLineToPoint(ctx, x + 8.0f, y - 9.0f);
    CGContextAddLineToPoint(ctx, x + 8.0f, y - 1.0f);
    CGContextStrokePath(ctx);
}

@end

// ------------------------------------------------------- Now Playing view ----

@implementation LTiPodNowPlayingView

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    [[UIColor whiteColor] setFill];
    CGContextFillRect(ctx, bounds);

    if (!self.track) {
        [[UIColor grayColor] set];
        [@"Nothing Playing" drawInRect:CGRectMake(20, bounds.size.height * 0.3f,
                                                  bounds.size.width - 40, 24)
                             withFont:[UIFont boldSystemFontOfSize:13.0f]
                        lineBreakMode:NSLineBreakByTruncatingTail
                            alignment:NSTextAlignmentCenter];
        return;
    }

    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    CGFloat margin = 8.0f;

    // Album art on the left, sized to leave room for text + bottom bar.
    CGFloat artSize = MIN(MAX(h - 46.0f, 64.0f), 130.0f);
    CGRect artRect = CGRectMake(margin, 12.0f, artSize, artSize);
    if (self.artImage) {
        // Aspect-fill (cover) like the main now-playing view: scale to fill the
        // square and center-crop any overflow.
        CGFloat scale = MAX(artRect.size.width / self.artImage.size.width,
                            artRect.size.height / self.artImage.size.height);
        CGFloat dw = self.artImage.size.width * scale;
        CGFloat dh = self.artImage.size.height * scale;
        CGRect drawRect = CGRectMake(artRect.origin.x + (artRect.size.width - dw) / 2.0f,
                                     artRect.origin.y + (artRect.size.height - dh) / 2.0f,
                                     dw, dh);
        CGContextSaveGState(ctx);
        CGContextAddRect(ctx, artRect);
        CGContextClip(ctx);
        [self.artImage drawInRect:drawRect];
        CGContextRestoreGState(ctx);
    } else {
        [[UIColor colorWithWhite:0.92f alpha:1.0f] setFill];
        CGContextFillRect(ctx, artRect);
        [[UIColor blackColor] set];
        UIFont *fa = LTiPodFAFont(24.0f);
        if (fa) {
            NSString *s = [NSString stringWithFormat:@"%C", (unichar)0xF001];
            CGSize sz = [s sizeWithFont:fa];
            [s drawAtPoint:CGPointMake(artRect.origin.x + (artSize - sz.width) / 2.0f,
                                       artRect.origin.y + (artSize - sz.height) / 2.0f - 2.0f)
                  withFont:fa];
        }
    }
    [[UIColor colorWithWhite:0.6f alpha:1.0f] setStroke];
    CGContextSetLineWidth(ctx, 1.0f);
    CGContextStrokeRect(ctx, artRect);

    // Text column to the right of the art, left-aligned.
    CGFloat tx = CGRectGetMaxX(artRect) + 8.0f;
    CGFloat tw = w - tx - margin;
    CGFloat y = 14.0f;
    [[UIColor blackColor] set];
    [self.track.title drawInRect:CGRectMake(tx, y, tw, 19)
                        withFont:[UIFont boldSystemFontOfSize:14.0f]
                   lineBreakMode:NSLineBreakByTruncatingTail
                       alignment:NSTextAlignmentLeft];

    y += 21;
    [[UIColor grayColor] set];
    [self.track.artist drawInRect:CGRectMake(tx, y, tw, 17)
                         withFont:[UIFont systemFontOfSize:12.0f]
                    lineBreakMode:NSLineBreakByTruncatingTail
                        alignment:NSTextAlignmentLeft];

    y += 19;
    UIFont *stateFont = [UIFont systemFontOfSize:12.0f];
    UIFont *fa = LTiPodFAFont(11.0f);
    unichar stateIcon = self.isPlaying ? (unichar)0xF04B : (unichar)0xF04C; // play / pause
    if (self.isPlaying) {
        [[UIColor colorWithRed:0.25f green:0.5f blue:0.95f alpha:1.0f] set];
    } else {
        [[UIColor grayColor] set];
    }
    CGFloat iconX = tx;
    if (fa) {
        NSString *si = [NSString stringWithFormat:@"%C", stateIcon];
        CGSize isz = [si sizeWithFont:fa];
        [si drawAtPoint:CGPointMake(iconX, y - 1.0f) withFont:fa];
        iconX += isz.width + 4.0f;
    }
    [self.isPlaying ? @"Playing" : @"Paused" drawAtPoint:CGPointMake(iconX, y)
                                                withFont:stateFont];

    // Bottom bar: volume bar while the user adjusts it, otherwise progress.
    CGFloat barY = h - 22.0f;
    if (barY < y + 12.0f) barY = y + 12.0f;
    CGFloat barW = w - margin * 2.0f;
    [[UIColor colorWithWhite:0.85f alpha:1.0f] setFill];
    CGContextFillRect(ctx, CGRectMake(margin, barY, barW, 4.0f));

    if (self.volumeMode) {
        CGFloat fill = self.volume < 0.0f ? 0.0f : (self.volume > 1.0f ? 1.0f : self.volume);
        [[UIColor colorWithRed:0.25f green:0.5f blue:0.95f alpha:1.0f] setFill];
        CGContextFillRect(ctx, CGRectMake(margin, barY, barW * fill, 4.0f));
        UIFont *vf = LTiPodFAFont(12.0f);
        UIFont *pf = [UIFont boldSystemFontOfSize:11.0f];
        [[UIColor grayColor] set];
        if (vf) {
            NSString *vol = [NSString stringWithFormat:@"%C", (unichar)0xF028]; // volume-up
            [vol drawAtPoint:CGPointMake(margin, barY + 8.0f) withFont:vf];
        }
        NSString *pct = [NSString stringWithFormat:@"%d%%", (int)(fill * 100.0f + 0.5f)];
        float pw = [pct sizeWithFont:pf].width;
        [[UIColor grayColor] set];
        [pct drawAtPoint:CGPointMake(w - margin - pw, barY + 8.0f) withFont:pf];
    } else {
        double total = self.total;
        double elapsed = self.elapsed;
        if (total <= 0) total = 1;
        if (elapsed < 0) elapsed = 0;
        CGFloat filledW = barW * (CGFloat)(elapsed / total);
        [[UIColor colorWithRed:0.25f green:0.5f blue:0.95f alpha:1.0f] setFill];
        CGContextFillRect(ctx, CGRectMake(margin, barY, filledW, 4.0f));

        NSInteger ei = (NSInteger)elapsed;
        NSInteger ti = (NSInteger)total;
        NSString *eStr = ti >= 3600 ? [NSString stringWithFormat:@"%d:%02d:%02d", (int)(ei/3600), (int)((ei%3600)/60), (int)(ei%60)]
                                    : [NSString stringWithFormat:@"%d:%02d", (int)(ei/60), (int)(ei%60)];
        NSString *tStr = ti >= 3600 ? [NSString stringWithFormat:@"%d:%02d:%02d", (int)(ti/3600), (int)((ti%3600)/60), (int)(ti%60)]
                                    : [NSString stringWithFormat:@"%d:%02d", (int)(ti/60), (int)(ti%60)];
        UIFont *timeFont = [UIFont systemFontOfSize:10.0f];
        [[UIColor grayColor] set];
        [eStr drawAtPoint:CGPointMake(margin, barY + 7.0f) withFont:timeFont];
        float tsw = [tStr sizeWithFont:timeFont].width;
        [tStr drawAtPoint:CGPointMake(w - margin - tsw, barY + 7.0f) withFont:timeFont];
    }
}

@end

// ------------------------------------------------------------- Search view ----

@implementation LTiPodSearchView

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat w = bounds.size.width;

    UIFont *qf = [UIFont boldSystemFontOfSize:12.0f];
    if (self.query.length) {
        [[UIColor colorWithWhite:0.05f alpha:1.0f] set];
        [self.query drawAtPoint:CGPointMake(8.0f, 6.0f) withFont:qf];
    } else {
        [[UIColor colorWithWhite:0.55f alpha:1.0f] set];
        [@"Type to search" drawAtPoint:CGPointMake(8.0f, 6.0f) withFont:qf];
    }

    CGFloat topY = LTiPodSearchKeyboardTop(bounds.size.height);
    UIFont *rf = [UIFont systemFontOfSize:11.0f];
    if (self.loading) {
        [[UIColor colorWithWhite:0.45f alpha:1.0f] set];
        [@"Searching…" drawAtPoint:CGPointMake(8.0f, 24.0f) withFont:rf];
    } else {
        NSInteger maxRows = (NSInteger)floorf((topY - 26.0f) / 15.0f);
        if (maxRows < 0) maxRows = 0;
        if (self.results.count) {
            for (NSInteger i = 0; i < maxRows && i < (NSInteger)self.results.count; i++) {
                LTTrack *track = [self.results objectAtIndex:(NSUInteger)i];
                NSString *line = track.title.length ? track.title : @"Unknown Song";
                if (track.artist.length) line = [NSString stringWithFormat:@"%@ — %@", track.artist, line];
                line = [self truncateString:line toWidth:w - 16.0f font:rf];
                [[UIColor colorWithWhite:0.15f alpha:1.0f] set];
                [line drawAtPoint:CGPointMake(8.0f, 24.0f + (CGFloat)i * 15.0f) withFont:rf];
            }
        }
    }

    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:0.8f alpha:1.0f].CGColor);
    CGContextSetLineWidth(ctx, 1.0f);
    CGContextMoveToPoint(ctx, 4.0f, topY - 4.0f);
    CGContextAddLineToPoint(ctx, w - 4.0f, topY - 4.0f);
    CGContextStrokePath(ctx);

    NSUInteger total = LTiPodSearchKeyCount();
    for (NSUInteger i = 0; i < total; i++) {
        CGRect kr;
        LTiPodSearchKeyRect(i, bounds.size, &kr);
        BOOL sel = (i == (NSUInteger)self.keyIndex);
        BOOL action = LTiPodSearchKeyAction(i) != 0;
        if (sel) {
            [[UIColor colorWithRed:0.15f green:0.40f blue:0.85f alpha:1.0f] set];
            UIRectFill(kr);
        } else {
            [[UIColor colorWithWhite:action ? 0.86f : 0.93f alpha:1.0f] setFill];
            UIRectFill(kr);
        }
        NSString *label = LTiPodSearchKeyLabel(i);
        UIFont *kf = [UIFont boldSystemFontOfSize:action ? 9.0f : 11.0f];
        [(sel ? [UIColor whiteColor] : [UIColor colorWithWhite:0.15f alpha:1.0f]) set];
        CGSize sz = [label sizeWithFont:kf];
        [label drawAtPoint:CGPointMake(kr.origin.x + (kr.size.width - sz.width) / 2.0f,
                                       kr.origin.y + (kr.size.height - sz.height) / 2.0f)
                   withFont:kf];
    }
}

- (NSString *)truncateString:(NSString *)str toWidth:(CGFloat)maxW font:(UIFont *)font {
    NSString *original = str;
    NSMutableString *s = [str mutableCopy];
    CGFloat target = maxW - 9.0f;
    while ([s sizeWithFont:font].width > target && s.length > 1) {
        [s deleteCharactersInRange:NSMakeRange(s.length - 1, 1)];
    }
    if (![s isEqualToString:original]) [s appendString:@"…"];
    return s;
}

@end

// -------------------------------------------------------------- Wheel view --

@implementation LTiPodWheelView {
    CGFloat centerX, centerY, wheelR;
    BOOL scrolling;
    CGFloat lastAngle;
    CGFloat accumulated;
    CGFloat scrollVelocity;   // deg/sec estimate for momentum
    NSTimeInterval lastMoveTime;
    NSTimeInterval lastVelTime;
    CGPoint gestureStartPoint;
    CGFloat gestureStartAngle;
    CGFloat loggedR;          // for one-shot diagnostics
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self prepareMetrics];
}

- (void)prepareMetrics {
    CGFloat bw = self.bounds.size.width;
    CGFloat bh = self.bounds.size.height;
    if (bw <= 0 || bh <= 0) return;
    centerX = bw / 2.0f;
    centerY = bh / 2.0f;
    wheelR = MIN(bw, bh) / 2.0f;
    if (fabs(wheelR - loggedR) > 0.5f) {
        loggedR = wheelR;
        LTLog(@"iPod wheel metrics bounds=(%.0f,%.0f) r=%.0f", bw, bh, wheelR);
    }
}

- (CGFloat)selectRadius {
    return wheelR * 0.40f;
}

- (CGFloat)buttonRadius {
    return (wheelR + [self selectRadius]) / 2.0f * 0.9f;
}

- (void)drawRect:(CGRect)rect {
    if (fabs(wheelR) < 0.001f) [self prepareMetrics];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGFloat selectR = [self selectRadius];

    // Housing color fills the whole view so the wheel blends into the body.
    [[UIColor colorWithWhite:0.18f alpha:1.0f] setFill];
    CGContextFillRect(ctx, self.bounds);

    // Wheel face: graphite ring slightly lighter than the housing, with a
    // recessed outer groove and an inner groove around the select disc.
    [[UIColor colorWithWhite:0.30f alpha:1.0f] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(centerX - wheelR, centerY - wheelR, wheelR * 2, wheelR * 2));
    [[UIColor colorWithWhite:0.14f alpha:1.0f] setStroke];
    CGContextSetLineWidth(ctx, 2.0f);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(centerX - wheelR + 1.0f, centerY - wheelR + 1.0f, wheelR * 2 - 2.0f, wheelR * 2 - 2.0f));
    [[UIColor colorWithWhite:0.14f alpha:1.0f] setStroke];
    CGContextSetLineWidth(ctx, 1.0f);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(centerX - selectR, centerY - selectR, selectR * 2, selectR * 2));

    // Center select disc: graphite to match the body, sitting above the ring.
    CGFloat selR = selectR - 4.0f;
    [[UIColor colorWithWhite:0.18f alpha:1.0f] setFill];
    CGContextFillEllipseInRect(ctx, CGRectMake(centerX - selR, centerY - selR, selR * 2, selR * 2));
    [[UIColor colorWithWhite:0.30f alpha:1.0f] setStroke];
    CGContextSetLineWidth(ctx, 1.0f);
    CGContextStrokeEllipseInRect(ctx, CGRectMake(centerX - selR, centerY - selR, selR * 2, selR * 2));

    CGFloat br = [self buttonRadius];
    UIFont *fa = LTiPodFAFont(16.0f);

    // Menu (top, red text).
    [[UIColor colorWithRed:0.95f green:0.35f blue:0.30f alpha:1.0f] set];
    [@"MENU" drawAtPoint:CGPointMake(centerX - 17.0f, centerY - br - 11.0f)
                withFont:[UIFont boldSystemFontOfSize:10.0f]];

    if (fa) {
        // Previous (left): fa-step-backward.
        [[UIColor colorWithWhite:0.92f alpha:1.0f] set];
        NSString *prev = [NSString stringWithFormat:@"%C", (unichar)0xF048];
        CGSize psz = [prev sizeWithFont:fa];
        [prev drawAtPoint:CGPointMake(centerX - br - psz.width - 6.0f, centerY - psz.height / 2.0f - 1.0f) withFont:fa];

        // Play/pause (bottom).
        unichar pp = self.showsPauseIcon ? (unichar)0xF04C : (unichar)0xF04B;
        NSString *play = [NSString stringWithFormat:@"%C", pp];
        CGSize qsz = [play sizeWithFont:fa];
        [play drawAtPoint:CGPointMake(centerX - qsz.width / 2.0f + 1.0f, centerY + br - qsz.height - 4.0f) withFont:fa];

        // Next (right): fa-step-forward.
        NSString *next = [NSString stringWithFormat:@"%C", (unichar)0xF051];
        CGSize nsz = [next sizeWithFont:fa];
        [next drawAtPoint:CGPointMake(centerX + br + 2.0f, centerY - nsz.height / 2.0f - 1.0f) withFont:fa];
    }
}

- (LTiPodWheelButton)buttonAtPoint:(CGPoint)p {
    CGFloat dx = p.x - centerX;
    CGFloat dy = p.y - centerY;
    CGFloat dist = sqrtf(dx * dx + dy * dy);
    if (dist <= [self selectRadius]) return LTiPodWheelButtonSelect;
    if (dist > wheelR) return LTiPodWheelButtonNone;

    // Nearest of the four button centers; within 26pt counts as a tap.
    CGFloat br = [self buttonRadius];
    CGFloat candidates[4][2] = {
        {0, -br},  // menu
        {-br, 0},  // previous
        {0, br},   // play/pause
        {br, 0},   // next
    };
    NSInteger best = -1;
    CGFloat bestD = 26.0f;
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat ddx = dx - candidates[i][0];
        CGFloat ddy = dy - candidates[i][1];
        CGFloat d = sqrtf(ddx * ddx + ddy * ddy);
        if (d < bestD) { bestD = d; best = i; }
    }
    if (best == 0) return LTiPodWheelButtonMenu;
    if (best == 1) return LTiPodWheelButtonPrevious;
    if (best == 2) return LTiPodWheelButtonPlayPause;
    if (best == 3) return LTiPodWheelButtonNext;
    return LTiPodWheelButtonNone;
}

- (BOOL)isRingZone:(CGPoint)p {
    // Entire ring between the center circle and the wheel edge scrolls, even
    // over the button spots — so a rotating thumb never gets interrupted.
    CGFloat dx = p.x - centerX;
    CGFloat dy = p.y - centerY;
    CGFloat dist = sqrtf(dx * dx + dy * dy);
    if (dist <= [self selectRadius]) return NO;
    if (dist > wheelR) return NO;
    return YES;
}

#pragma mark - Touch handling

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (fabs(wheelR) < 0.001f) [self prepareMetrics];
    UITouch *touch = [touches anyObject];
    CGPoint p = [touch locationInView:self];
    BOOL ring = [self isRingZone:p];
    LTLog(@"iPod touchBegan (%d,%d) ring=%d r=%.0f", (int)p.x, (int)p.y, ring, wheelR);
    if (ring) {
        scrolling = YES;
        lastAngle = [self angleAtPoint:p];
        gestureStartAngle = lastAngle;
        gestureStartPoint = p;
        accumulated = 0.0f;
        scrollVelocity = 0.0f;
        lastMoveTime = touch.timestamp;
        lastVelTime = 0.0;
    } else {
        scrolling = NO;
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint p = [touch locationInView:self];
    if (!scrolling) return;
    // A finger can slip off the ring onto the center disc or even off the
    // wheel; the gesture stays alive until the finger lifts. Only the dead
    // zone right on the wheel centre is ignored, where the angle would jump
    // around from touch jitter.
    CGFloat cx = p.x - centerX;
    CGFloat cy = p.y - centerY;
    if (cx * cx + cy * cy <= 100.0f) return; // radius <= 10pt
    // Rotational scrolling: clockwise (positive angle) moves forward/down,
    // counter-clockwise moves up. Deltas are radians; keep `accumulated` as
    // degrees so it maps 1:1 onto the list's per-row scale.
    CGFloat a = [self angleAtPoint:p];
    CGFloat delta = [self unwrapDelta:a - lastAngle];
    lastAngle = a;
    if (delta != 0.0f) {
        CGFloat deltaDeg = delta * (180.0f / (CGFloat)M_PI);
        accumulated += deltaDeg;
        NSTimeInterval now = touch.timestamp;
        CGFloat dt = (CGFloat)(now - lastMoveTime);
        if (dt > 0.02f) {
            CGFloat inst = deltaDeg / dt; // deg/sec
            if (now - lastVelTime < 0.12) {
                scrollVelocity = scrollVelocity * 0.6f + inst * 0.4f;
            } else {
                scrollVelocity = inst;
            }
            lastVelTime = now;
        }
        lastMoveTime = now;
    }
    if (fabs(accumulated) >= kIPodScrollMinDegrees) {
        CGFloat send = accumulated;
        accumulated = 0.0f;
        LTLog(@"iPod wheel rot %.1f° vel=%.0f", send, scrollVelocity);
        [self.delegate iPodWheel:self scrolledByDegrees:send];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint p = [touch locationInView:self];
    if (!scrolling) {
        // Center-circle press.
        LTiPodWheelButton button = [self buttonAtPoint:p];
        if (button != LTiPodWheelButtonNone) {
            LTLog(@"iPod tap center fire %ld", (long)button);
            [self fireButton:button];
        }
        return;
    }
    // A press on the ring that barely rotated is a button tap.
    CGFloat rotated = fabs([self unwrapDelta:[self angleAtPoint:p] - gestureStartAngle]);
    CGFloat moved = sqrtf(powf(p.x - gestureStartPoint.x, 2) + powf(p.y - gestureStartPoint.y, 2));
    if (rotated < 0.4f && moved < 8.0f) {
        LTiPodWheelButton button = [self buttonAtPoint:p];
        if (button != LTiPodWheelButtonNone) {
            LTLog(@"iPod tap ring fire %ld", (long)button);
            [self fireButton:button];
        }
        return;
    }
    if (fabs(accumulated) >= kIPodScrollMinDegrees) {
        [self.delegate iPodWheel:self scrolledByDegrees:accumulated];
    }
    accumulated = 0.0f;
    scrolling = NO;
    [self.delegate iPodWheelDidEndScrolling:self velocity:scrollVelocity];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    scrolling = NO;
    accumulated = 0.0f;
    scrollVelocity = 0.0f;
}

- (void)fireButton:(LTiPodWheelButton)button {
    [self.delegate iPodWheel:self buttonPressed:button];
}

- (CGFloat)angleAtPoint:(CGPoint)p {
    return atan2f(p.y - centerY, p.x - centerX);
}

- (CGFloat)unwrapDelta:(CGFloat)delta {
    while (delta > M_PI) delta -= 2.0f * M_PI;
    while (delta < -M_PI) delta += 2.0f * M_PI;
    return delta;
}

@end