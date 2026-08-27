#import "LTMediaCell.h"
#import "LTYouTubeClient.h"

@implementation LTMediaCell

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
