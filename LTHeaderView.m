#import "LTHeaderView.h"
#import <QuartzCore/QuartzCore.h>
#import "LTYouTubeClient.h"
#import "LTTheme.h"

#define LT_PADDING 12.0f

// Height of the actions row, and the gap above it. The header starts at 200
// with no actions row and grows by this much when one is shown.
#define LT_ACTIONS_HEIGHT 44.0f

@implementation LTHeaderView

- (id)initWithWidth:(CGFloat)width {
    self = [super initWithFrame:CGRectMake(0, 0, width, 200)];
    if (self) {
        _artworkView = [[UIImageView alloc] initWithFrame:CGRectMake((width - 140) / 2.0f, 16, 140, 140)];
        _artworkView.backgroundColor = [LTTheme placeholder];
        _artworkView.contentMode = UIViewContentModeScaleAspectFill;
        _artworkView.clipsToBounds = YES;
        [self addSubview:_artworkView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(LT_PADDING, 162, width - LT_PADDING * 2, 20)];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.font = [UIFont boldSystemFontOfSize:17];
        // UIKit's default label colour is black on every iOS before 13, so on
        // the modern dark theme the artist's name was black on a dark canvas.
        _titleLabel.textColor = [LTTheme text];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(LT_PADDING, 182, width - LT_PADDING * 2, 16)];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.font = [UIFont systemFontOfSize:13];
        _subtitleLabel.textColor = [LTTheme secondaryText];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_subtitleLabel];

        _playAllButton = [self actionButtonWithTitle:@""];
        _playAllButton.hidden = YES;
        [_playAllButton addTarget:self action:@selector(playAllTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_playAllButton];

        _shuffleAllButton = [self actionButtonWithTitle:@""];
        _shuffleAllButton.hidden = YES;
        [_shuffleAllButton addTarget:self action:@selector(shuffleAllTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_shuffleAllButton];
    }
    return self;
}

- (UIButton *)actionButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[LTTheme text] forState:UIControlStateNormal];
    [button setTitleColor:[LTTheme secondaryText] forState:UIControlStateHighlighted];
    button.backgroundColor = [LTTheme fill];
    button.layer.cornerRadius = [LTTheme cornerRadius];
    button.clipsToBounds = YES;
    return button;
}

- (void)configurePlayAllTitle:(NSString *)playTitle shuffleTitle:(NSString *)shuffleTitle {
    BOOL show = playTitle.length > 0 || shuffleTitle.length > 0;
    CGFloat width = self.bounds.size.width;
    CGFloat gap = 10.0f;
    CGFloat buttonWidth = width > 0 ? (width - LT_PADDING * 2 - gap) / 2.0f : 0.0f;
    CGFloat y = 206.0f;

    self.playAllButton.hidden = !playTitle.length;
    self.shuffleAllButton.hidden = !shuffleTitle.length;
    [self.playAllButton setTitle:playTitle forState:UIControlStateNormal];
    [self.shuffleAllButton setTitle:shuffleTitle forState:UIControlStateNormal];

    if (playTitle.length) {
        self.playAllButton.frame = CGRectMake(LT_PADDING, y, buttonWidth, LT_ACTIONS_HEIGHT - 8.0f);
    }
    if (shuffleTitle.length) {
        self.shuffleAllButton.frame = CGRectMake(LT_PADDING + buttonWidth + gap, y, buttonWidth, LT_ACTIONS_HEIGHT - 8.0f);
    }

    // tableHeaderView is laid out from its frame height, so growing it here is
    // what makes room for the buttons.
    CGFloat height = show ? 200.0f + LT_ACTIONS_HEIGHT : 200.0f;
    if (fabs(self.frame.size.height - height) < 0.5f) return;
    self.frame = CGRectMake(0, 0, width, height);
}

- (void)playAllTapped:(id)sender {
    if (self.onAction) self.onAction(NO);
}

- (void)shuffleAllTapped:(id)sender {
    if (self.onAction) self.onAction(YES);
}

- (void)setArtworkURL:(NSString *)urlString {
    _artworkView.image = nil;
    if (!urlString.length) return;
    __unsafe_unretained LTHeaderView *weakSelf = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:urlString completion:^(UIImage *image) {
        LTHeaderView *strongSelf = weakSelf;
        if (strongSelf && image) {
            strongSelf.artworkView.image = image;
        }
    }];
}

@end
