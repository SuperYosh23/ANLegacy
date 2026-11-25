#import "S6PlayerBar.h"
#import "S6Player.h"
#import "S6Router.h"
#import "S6Theme.h"
#import "S6Models.h"
#import "S6Catalog.h"
#import "S6ImageLoader.h"
#import "S6Utils.h"
#import "S6Common.h"
#import <MediaPlayer/MediaPlayer.h>

@interface S6PlayerBar ()
@property (nonatomic) BOOL compact;
@property (nonatomic, strong) UIImageView *background;
@property (nonatomic, strong) S6ImageView *art;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UIButton *songButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *previousButton;
@property (nonatomic, strong) UIButton *shuffleButton;
@property (nonatomic, strong) UIButton *repeatButton;
@property (nonatomic, strong) UIButton *heartButton;
@property (nonatomic, strong) UIButton *queueButton;
@property (nonatomic, strong) UIButton *lyricsButton;
@property (nonatomic, strong) UISlider *progress;
@property (nonatomic, strong) UIView *thinProgress;
@property (nonatomic, strong) UILabel *elapsedLabel;
@property (nonatomic, strong) UILabel *remainingLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) MPVolumeView *volume;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL scrubbing;
@property (nonatomic, copy) NSString *shownURI;
@property (nonatomic) BOOL liked;
@end

@implementation S6PlayerBar

+ (CGFloat)heightCompact:(BOOL)compact { return compact ? 54 : 72; }

- (instancetype)initWithFrame:(CGRect)frame compact:(BOOL)compact
{
    if ((self = [super initWithFrame:frame])) {
        _compact = compact;
        S6Theme *theme = [S6Theme shared];
        _background = [[UIImageView alloc] initWithImage:[theme playerBarImage]];
        _background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _background.frame = self.bounds;
        [self addSubview:_background];
        _art = [[S6ImageView alloc] initWithFrame:CGRectZero];
        _art.contentMode = UIViewContentModeScaleAspectFill;
        _art.clipsToBounds = YES;
        [self addSubview:_art];
        _titleLabel = [self label:[theme boldBodyFont] color:[theme primaryTextColor]];
        _artistLabel = [self label:[theme smallFont] color:[theme secondaryTextColor]];
        _songButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_songButton addTarget:self action:@selector(openNowPlaying) forControlEvents:UIControlEventTouchUpInside];
        _songButton.accessibilityLabel = L(@"Now playing");
        [self addSubview:_songButton];
        _playButton = [self button:S6IconPlay size:compact ? 26 : 30 action:@selector(togglePlay)];
        _nextButton = [self button:S6IconNext size:compact ? 22 : 22 action:@selector(next)];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];
        if (compact) {
            _thinProgress = [[UIView alloc] initWithFrame:CGRectZero];
            _thinProgress.backgroundColor = [theme accentColor];
            [self addSubview:_thinProgress];
        } else {
            _previousButton = [self button:S6IconPrevious size:22 action:@selector(previous)];
            _shuffleButton = [self button:S6IconShuffle size:20 action:@selector(toggleShuffle)];
            _repeatButton = [self button:S6IconRepeat size:20 action:@selector(cycleRepeat)];
            _heartButton = [self button:S6IconHeart size:20 action:@selector(toggleLike)];
            _queueButton = [self button:S6IconQueue size:20 action:@selector(openQueue)];
            _lyricsButton = [self button:S6IconLyrics size:20 action:@selector(openLyrics)];
            _progress = [[UISlider alloc] initWithFrame:CGRectZero];
            [_progress addTarget:self action:@selector(scrubStarted) forControlEvents:UIControlEventTouchDown];
            [_progress addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            [_progress addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
            [self addSubview:_progress];
            _elapsedLabel = [self label:[UIFont fontWithName:@"HelveticaNeue" size:11] ?: [UIFont systemFontOfSize:11] color:[theme secondaryTextColor]];
            _elapsedLabel.textAlignment = NSTextAlignmentRight;
            _remainingLabel = [self label:[UIFont fontWithName:@"HelveticaNeue" size:11] ?: [UIFont systemFontOfSize:11] color:[theme secondaryTextColor]];
            _volume = [[MPVolumeView alloc] initWithFrame:CGRectZero];
            _volume.showsRouteButton = YES;
            [_volume setMinimumVolumeSliderImage:[theme sliderTrackImageFilled:YES] forState:UIControlStateNormal];
            [_volume setMaximumVolumeSliderImage:[theme sliderTrackImageFilled:NO] forState:UIControlStateNormal];
            [_volume setVolumeThumbImage:[theme sliderThumbImage] forState:UIControlStateNormal];
            [self addSubview:_volume];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(update) name:S6PlayerDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:S6LibraryDidChangeNotification object:nil];
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [self update];
    }
    return self;
}

- (void)dealloc
{
    [_timer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)willMoveToWindow:(UIWindow *)newWindow
{
    // (the timer keeps the bar alive; it stops when the bar leaves)
    if (!newWindow) { [self.timer invalidate]; self.timer = nil; }
    else if (!self.timer) self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

- (UILabel *)label:(UIFont *)font color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.6];
    l.shadowOffset = CGSizeMake(0, -1);
    [self addSubview:l];
    return l;
}

- (UIButton *)button:(S6Icon)icon size:(CGFloat)size action:(SEL)action
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:[[S6Theme shared] icon:icon size:size] forState:UIControlStateNormal];
    b.showsTouchWhenHighlighted = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

- (void)setBottomInset:(CGFloat)bottomInset
{
    if (bottomInset == _bottomInset) return;
    _bottomInset = bottomInset;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    s.height -= self.bottomInset;   // (the part over the home indicator of iOS 11+ stays empty)
    if (self.compact) {
        self.thinProgress.frame = CGRectMake(0, 0, self.thinProgress.frame.size.width, 2);
        self.art.frame = CGRectMake(6, 6, s.height - 12, s.height - 12);
        CGFloat x = s.height + 2;
        self.nextButton.frame = CGRectMake(s.width - 46, 0, 44, s.height);
        self.playButton.frame = CGRectMake(s.width - 92, 0, 44, s.height);
        self.spinner.center = self.playButton.center;
        self.titleLabel.frame = CGRectMake(x, 9, s.width - x - 96, 19);
        self.artistLabel.frame = CGRectMake(x, 28, s.width - x - 96, 16);
        self.songButton.frame = CGRectMake(0, 0, s.width - 96, s.height);
        return;
    }
    self.art.frame = CGRectMake(8, 8, 56, 56);
    CGFloat leftW = MIN(260, s.width * 0.28);
    self.titleLabel.frame = CGRectMake(74, 16, leftW - 74, 20);
    self.artistLabel.frame = CGRectMake(74, 37, leftW - 74, 17);
    self.songButton.frame = CGRectMake(0, 0, leftW, s.height);
    CGFloat rightW = MIN(300, s.width * 0.3);
    CGFloat center = leftW + (s.width - leftW - rightW) / 2;
    CGFloat cy = 22;
    self.playButton.frame = CGRectMake(center - 22, cy - 20, 44, 40);
    self.spinner.center = self.playButton.center;
    self.previousButton.frame = CGRectMake(center - 74, cy - 20, 44, 40);
    self.nextButton.frame = CGRectMake(center + 30, cy - 20, 44, 40);
    self.shuffleButton.frame = CGRectMake(center - 124, cy - 20, 40, 40);
    self.repeatButton.frame = CGRectMake(center + 84, cy - 20, 40, 40);
    CGFloat barW = MIN(s.width - leftW - rightW - 20, 520);
    self.elapsedLabel.frame = CGRectMake(center - barW / 2 - 46, 44, 40, 20);
    self.progress.frame = CGRectMake(center - barW / 2, 43, barW, 22);
    self.remainingLabel.frame = CGRectMake(center + barW / 2 + 6, 44, 44, 20);
    CGFloat rx = s.width - rightW;
    self.heartButton.frame = CGRectMake(rx, 16, 40, 40);
    self.lyricsButton.frame = CGRectMake(rx + 40, 16, 40, 40);
    self.queueButton.frame = CGRectMake(rx + 80, 16, 40, 40);
    self.volume.frame = CGRectMake(rx + 128, 28, rightW - 140, 22);
}

#pragma mark - State

- (void)update
{
    S6Player *player = [S6Player shared];
    S6Theme *theme = [S6Theme shared];
    S6Track *t = player.currentTrack;
    self.titleLabel.text = t ? [S6Utils displayText:t.name] : L(@"Nothing playing");
    self.artistLabel.text = t ? [S6Utils displayText:[t artistNames]] : @"";
    [self.art setImageURL:[t imageURLForSize:120] placeholder:[theme artPlaceholderWithSize:56]];
    [self.playButton setImage:[theme icon:player.playing ? S6IconPause : S6IconPlay size:self.compact ? 26 : 30] forState:UIControlStateNormal];
    if (player.buffering && player.playing) { [self.spinner startAnimating]; self.playButton.alpha = 0.2; }
    else { [self.spinner stopAnimating]; self.playButton.alpha = 1; }
    UIColor *on = [theme accentColor], *off = [UIColor whiteColor];
    [self.shuffleButton setImage:[theme icon:S6IconShuffle size:20 color:player.shuffle ? on : off] forState:UIControlStateNormal];
    [self.repeatButton setImage:[theme icon:player.repeat == S6RepeatOne ? S6IconRepeatOne : S6IconRepeat size:20 color:player.repeat != S6RepeatOff ? on : off] forState:UIControlStateNormal];
    if (t.uri && ![t.uri isEqualToString:self.shownURI]) {
        self.shownURI = t.uri;
        self.liked = NO;
        [self showLiked];
        if (t.trackId.length && !t.isEpisode) {
            NSString *uri = t.uri;
            [S6Catalog areSaved:@[ t.uri ] completion:^(NSArray *savedList, NSError *savedError) {
                BOOL saved = [savedList.firstObject boolValue];
                if (![uri isEqualToString:self.shownURI]) return;
                self.liked = saved;
                [self showLiked];
            }];
        }
    }
    [self tick];
}

- (void)libraryChanged
{
    self.shownURI = nil;
    [self update];
}

- (void)showLiked
{
    S6Theme *theme = [S6Theme shared];
    [self.heartButton setImage:[theme icon:self.liked ? S6IconHeartFilled : S6IconHeart size:20 color:self.liked ? [theme accentColor] : [UIColor whiteColor]] forState:UIControlStateNormal];
}

- (void)tick
{
    if (!self.window) return;
    S6Player *player = [S6Player shared];
    NSInteger duration = player.durationMs, position = player.positionMs;
    if (self.compact) {
        CGFloat w = duration > 0 ? self.bounds.size.width * MIN(1.0, (double)position / duration) : 0;
        self.thinProgress.frame = CGRectMake(0, 0, w, 2);
        return;
    }
    if (self.scrubbing) return;
    self.progress.value = duration > 0 ? (float)position / (float)duration : 0;
    self.elapsedLabel.text = S6FormatDurationMs(position);
    self.remainingLabel.text = duration > 0 ? [@"-" stringByAppendingString:S6FormatDurationMs(MAX(0, duration - position))] : @"";
    if (player.buffering && player.playing) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
    self.playButton.alpha = self.spinner.isAnimating ? 0.2 : 1;
}

#pragma mark - Actions

- (void)togglePlay { [[S6Player shared] togglePlay]; }
- (void)next { [[S6Player shared] next]; }
- (void)previous { [[S6Player shared] previous]; }
- (void)toggleShuffle { S6Player *p = [S6Player shared]; p.shuffle = !p.shuffle; }

- (void)cycleRepeat
{
    S6Player *p = [S6Player shared];
    p.repeat = p.repeat == S6RepeatOff ? S6RepeatAll : p.repeat == S6RepeatAll ? S6RepeatOne : S6RepeatOff;
}

- (void)toggleLike
{
    S6Track *t = [S6Player shared].currentTrack;
    if (!t.trackId.length || t.isEpisode) return;
    BOOL like = !self.liked;
    self.liked = like;
    [self showLiked];
    [S6Catalog setSaved:like uris:@[ t.uri ] completion:^(NSError *error) {
        if (error) { self.liked = !like; [self showLiked]; [S6Router toast:error.localizedDescription]; return; }
        [S6Router toast:like ? L(@"Added to Liked Songs") : L(@"Removed from Liked Songs")];
    }];
}

- (void)openNowPlaying { if ([S6Player shared].currentTrack) [S6Router showNowPlaying]; }
- (void)openQueue { [[NSNotificationCenter defaultCenter] postNotificationName:@"S6ShowQueue" object:nil]; }
- (void)openLyrics { [[NSNotificationCenter defaultCenter] postNotificationName:@"S6ShowLyrics" object:nil]; }

- (void)scrubStarted { self.scrubbing = YES; }

- (void)scrubMoved
{
    NSInteger duration = [S6Player shared].durationMs;
    NSInteger at = (NSInteger)(self.progress.value * duration);
    self.elapsedLabel.text = S6FormatDurationMs(at);
    self.remainingLabel.text = [@"-" stringByAppendingString:S6FormatDurationMs(MAX(0, duration - at))];
}

- (void)scrubEnded
{
    NSInteger duration = [S6Player shared].durationMs;
    if (duration > 0) [[S6Player shared] seekToMs:(NSInteger)(self.progress.value * duration)];
    self.scrubbing = NO;
}

@end
