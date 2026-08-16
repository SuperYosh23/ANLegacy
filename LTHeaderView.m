#import "LTHeaderView.h"
#import "LTYouTubeClient.h"

#define LT_PADDING 12.0f

@implementation LTHeaderView

- (id)initWithWidth:(CGFloat)width {
    self = [super initWithFrame:CGRectMake(0, 0, width, 200)];
    if (self) {
        _artworkView = [[UIImageView alloc] initWithFrame:CGRectMake((width - 140) / 2.0f, 16, 140, 140)];
        _artworkView.backgroundColor = [UIColor lightGrayColor];
        _artworkView.contentMode = UIViewContentModeScaleAspectFill;
        _artworkView.clipsToBounds = YES;
        [self addSubview:_artworkView];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(LT_PADDING, 162, width - LT_PADDING * 2, 20)];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.font = [UIFont boldSystemFontOfSize:17];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(LT_PADDING, 182, width - LT_PADDING * 2, 16)];
        _subtitleLabel.textAlignment = NSTextAlignmentCenter;
        _subtitleLabel.font = [UIFont systemFontOfSize:13];
        _subtitleLabel.textColor = [UIColor grayColor];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_subtitleLabel];
    }
    return self;
}

- (void)setArtworkURL:(NSString *)urlString {
    _artworkView.image = nil;
    if (!urlString.length) return;
    __weak LTHeaderView *weakSelf = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:urlString completion:^(UIImage *image) {
        LTHeaderView *strongSelf = weakSelf;
        if (strongSelf && image) {
            strongSelf.artworkView.image = image;
        }
    }];
}

@end
