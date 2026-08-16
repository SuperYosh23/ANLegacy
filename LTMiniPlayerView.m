#import "LTMiniPlayerView.h"
#import "LTPlayerController.h"
#import "LTYouTubeClient.h"
#import "LTLog.h"
#import <QuartzCore/QuartzCore.h>

NSString *const LTNowPlayingDidAppearNotification = @"LTNowPlayingDidAppearNotification";
NSString *const LTNowPlayingDidDisappearNotification = @"LTNowPlayingDidDisappearNotification";
NSString *const LTMiniPlayerVisibilityDidChangeNotification = @"LTMiniPlayerVisibilityDidChangeNotification";

@interface LTMiniPlayerView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL nowPlayingVisible;
@end

@implementation LTMiniPlayerView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.12f alpha:0.96f];
        self.layer.borderWidth = 0.5f;
        self.layer.borderColor = [[UIColor colorWithWhite:0.45f alpha:1.0f] CGColor];

        self.artworkView = [[UIImageView alloc] init];
        self.artworkView.backgroundColor = [UIColor colorWithWhite:0.25f alpha:1.0f];
        self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
        self.artworkView.clipsToBounds = YES;
        [self addSubview:self.artworkView];

        self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        [self addSubview:self.spinner];

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:self.titleLabel];

        self.artistLabel = [[UILabel alloc] init];
        self.artistLabel.font = [UIFont systemFontOfSize:10];
        self.artistLabel.textColor = [UIColor colorWithWhite:0.75f alpha:1.0f];
        self.artistLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:self.artistLabel];

        self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.playButton setImage:[UIImage imageNamed:@"IcoPause"] forState:UIControlStateNormal];
        [self.playButton addTarget:self action:@selector(playTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.playButton];

        self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [self.nextButton setImage:[UIImage imageNamed:@"IcoNext"] forState:UIControlStateNormal];
        [self.nextButton addTarget:self action:@selector(nextTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.nextButton];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(refresh) name:LTPlayerTrackDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(refresh) name:LTPlayerStateDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(refresh) name:LTPlayerQueueDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(refresh) name:LTPlayerDidFinishQueueNotification object:nil];
        [nc addObserver:self selector:@selector(nowPlayingDidAppear:) name:LTNowPlayingDidAppearNotification object:nil];
        [nc addObserver:self selector:@selector(nowPlayingDidDisappear:) name:LTNowPlayingDidDisappearNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    CGFloat inset = 4.0f;
    CGFloat artSize = height - inset * 2.0f;
    self.artworkView.frame = CGRectMake(inset, inset, artSize, artSize);
    self.spinner.center = self.artworkView.center;

    CGFloat buttonSize = height;
    self.nextButton.frame = CGRectMake(width - buttonSize, 0, buttonSize, buttonSize);
    self.playButton.frame = CGRectMake(width - buttonSize * 2.0f, 0, buttonSize, buttonSize);

    CGFloat labelX = CGRectGetMaxX(self.artworkView.frame) + 8.0f;
    CGFloat labelRight = self.playButton.frame.origin.x - 8.0f;
    self.titleLabel.frame = CGRectMake(labelX, 9.0f, labelRight - labelX, 14.0f);
    self.artistLabel.frame = CGRectMake(labelX, 25.0f, labelRight - labelX, 12.0f);
}

- (void)refresh {
    LTTrack *track = [[LTPlayerController sharedController] currentTrack];
    BOOL shouldShow = (track != nil && !self.nowPlayingVisible);
    [self setVisible:shouldShow];
    if (!shouldShow) return;

    self.titleLabel.text = track.title;
    NSMutableString *artist = [NSMutableString string];
    if (track.artist.length) [artist appendString:track.artist];
    if (track.album.length) {
        if (artist.length) [artist appendString:@"  •  "];
        [artist appendString:track.album];
    }
    self.artistLabel.text = artist;

    self.artworkView.image = nil;
    if (track.thumbnailURL.length) {
        [[LTYouTubeClient sharedClient] loadImageWithURL:track.thumbnailURL completion:^(UIImage *image) {
            if (image && [track.videoId isEqualToString:[[LTPlayerController sharedController] currentTrack].videoId]) {
                self.artworkView.image = image;
            }
        }];
    }

    LTPlayerController *controller = [LTPlayerController sharedController];
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
}

#pragma mark - Visibility

- (void)setVisible:(BOOL)visible {
    if (self.hidden == !visible) return;
    self.hidden = !visible;
    [[NSNotificationCenter defaultCenter] postNotificationName:LTMiniPlayerVisibilityDidChangeNotification
                                                        object:self
                                                      userInfo:@{@"visible": @(visible)}];
}

#pragma mark - Now Playing screen visibility

- (void)nowPlayingDidAppear:(NSNotification *)notification {
    self.nowPlayingVisible = YES;
    [self setVisible:NO];
}

- (void)nowPlayingDidDisappear:(NSNotification *)notification {
    self.nowPlayingVisible = NO;
    [self refresh];
}

#pragma mark - Actions

- (void)playTapped:(id)sender {
    [[LTPlayerController sharedController] togglePlayPause];
}

- (void)nextTapped:(id)sender {
    [[LTPlayerController sharedController] nextTrack];
}

- (void)tapped:(UIGestureRecognizer *)gestureRecognizer {
    if (self.onOpenPlayer) self.onOpenPlayer();
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if ([touch.view isKindOfClass:[UIControl class]]) return NO;
    return YES;
}

@end
