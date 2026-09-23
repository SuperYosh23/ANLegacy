#import "LTMediaCell.h"
#import "LTYouTubeClient.h"
#import "LTTextUtils.h"

@implementation LTMediaCell {
    NSString *_cachedFullTitle;
    CGFloat _cachedMaxWidth;
    UIFont *_cachedFont;
    NSString *_cachedTruncatedText;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.imageView.contentMode = UIViewContentModeScaleAspectFill;
        self.imageView.clipsToBounds = YES;
        self.imageView.layer.cornerRadius = 4.0f;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.imageView.image) {
        CGFloat height = self.bounds.size.height - 8.0f;
        CGFloat width = height;
        self.imageView.frame = CGRectMake(8.0f, 4.0f, width, height);
        self.textLabel.frame = CGRectMake(CGRectGetMaxX(self.imageView.frame) + 8.0f,
                                          self.textLabel.frame.origin.y,
                                          self.bounds.size.width - CGRectGetMaxX(self.imageView.frame) - 16.0f,
                                          self.textLabel.frame.size.height);
        self.detailTextLabel.frame = CGRectMake(CGRectGetMaxX(self.imageView.frame) + 8.0f,
                                                self.detailTextLabel.frame.origin.y,
                                                self.bounds.size.width - CGRectGetMaxX(self.imageView.frame) - 16.0f,
                                                self.detailTextLabel.frame.size.height);
    }
    [self lt_updateTruncatedTitle];
}

- (void)lt_updateTruncatedTitle {
    UILabel *label = self.textLabel;
    if (!label) return;
    NSString *full = label.text;
    if (_cachedFullTitle.length && [full isEqualToString:_cachedTruncatedText]) {
        full = _cachedFullTitle;
    }
    if (!full.length) return;
    CGFloat maxWidth = self.bounds.size.width * LTListTitleWidthFraction - label.frame.origin.x;
    if (maxWidth <= 0.0f) return;
    UIFont *font = label.font;
    if ([full isEqualToString:_cachedFullTitle] &&
        maxWidth == _cachedMaxWidth &&
        (font == _cachedFont || [font isEqual:_cachedFont])) {
        if (![label.text isEqualToString:_cachedTruncatedText]) {
            label.text = _cachedTruncatedText;
        }
        return;
    }
    _cachedFullTitle = [full copy];
    _cachedMaxWidth = maxWidth;
    _cachedFont = font;
    _cachedTruncatedText = LTTruncatedTextToWidth(full, font, maxWidth);
    label.text = _cachedTruncatedText;
}

- (void)setImageFromURL:(NSString *)urlString {
    self.imageURL = urlString;
    self.imageView.image = nil;
    if (!urlString.length) return;
    NSString *artURL = [[LTYouTubeClient sharedClient] highResThumbnailURL:urlString];
    __weak LTMediaCell *weakCell = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:artURL completion:^(UIImage *image) {
        LTMediaCell *cell = weakCell;
        if (!cell) return;
        if ([cell.imageURL isEqualToString:urlString]) {
            cell.imageView.image = image;
            [cell setNeedsLayout];
        }
    }];
}

@end
