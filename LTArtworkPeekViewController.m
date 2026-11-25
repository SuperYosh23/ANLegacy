#import "LTArtworkPeekViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "LTModel.h"
#import "LTYouTubeClient.h"
#import "LTTheme.h"

// The artwork is capped so the card has a height that does not depend on the
// screen width; only its horizontal position changes.
// The card is wider than the Now Playing artwork (which is capped at
// screenWidth - 24 by that layout), so the peek never shows a smaller cover than
// the full view does. The cap only guards very wide screens.
static const CGFloat kLTArtworkMaxSide = 360.0f;
static const CGFloat kLTArtworkMargin = 8.0f;
static const CGFloat kLTArtworkTop = 20.0f;

@interface LTArtworkPeekViewController ()
@property (nonatomic, strong) LTTrack *track;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *artistLabel;
@end

@implementation LTArtworkPeekViewController

- (instancetype)initWithTrack:(LTTrack *)track image:(UIImage *)image {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _track = track;
        _image = image;
    }
    return self;
}

// A zero width asks UIKit to pick one that fits, instead of pinning the card to
// a fixed width that may be wider than the screen.
- (CGSize)preferredContentSize {
    CGFloat height = kLTArtworkTop + kLTArtworkMaxSide + 10.0f + 22.0f + 20.0f + 16.0f;
    return CGSizeMake(0.0f, height);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [LTTheme cellBackground];

    self.artworkView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.artworkView.contentMode = UIViewContentModeScaleAspectFill;
    self.artworkView.clipsToBounds = YES;
    self.artworkView.layer.cornerRadius = [LTTheme largeCornerRadius];
    self.artworkView.backgroundColor = [LTTheme placeholder];
    self.artworkView.image = self.image;
    [self.view addSubview:self.artworkView];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = self.track.title;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.textColor = [LTTheme text];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:self.titleLabel];

    self.artistLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.artistLabel.text = self.track.artist;
    self.artistLabel.font = [UIFont systemFontOfSize:14];
    self.artistLabel.textColor = [LTTheme secondaryText];
    self.artistLabel.textAlignment = NSTextAlignmentCenter;
    self.artistLabel.backgroundColor = [UIColor clearColor];
    self.artistLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.view addSubview:self.artistLabel];

    // The on-screen artwork is small; fetch the high-resolution copy so the card
    // is not just a magnification of a thumbnail.
    if (!self.image) [self loadHighResolutionArtwork];
}

- (void)loadHighResolutionArtwork {
    if (!self.track.thumbnailURL.length) return;
    NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:self.track.thumbnailURL];
    if (!artURL.length) return;
    __unsafe_unretained LTArtworkPeekViewController *weakSelf = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
        if (image) weakSelf.artworkView.image = image;
    }];
}

// Laid out here rather than in -viewDidLoad because UIKit resizes the peek
// container after loading the view; frames computed against the initial bounds
// would be positioned for a width the card never gets.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    if (width < 1.0f) return;

    CGFloat side = width - kLTArtworkMargin * 2.0f;
    if (side > kLTArtworkMaxSide) side = kLTArtworkMaxSide;
    if (side < 1.0f) side = 1.0f;

    // Centre the capped square horizontally.
    self.artworkView.frame = CGRectMake(floorf((width - side) * 0.5f), kLTArtworkTop, side, side);

    CGFloat textY = kLTArtworkTop + side + 10.0f;
    self.titleLabel.frame = CGRectMake(16.0f, textY, width - 32.0f, 22.0f);
    self.artistLabel.frame = CGRectMake(16.0f, textY + 22.0f, width - 32.0f, 20.0f);
}

@end