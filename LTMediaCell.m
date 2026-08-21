#import "LTMediaCell.h"
#import "LTYouTubeClient.h"

@implementation LTMediaCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.imageView.contentMode = UIViewContentModeScaleAspectFill;
        self.imageView.clipsToBounds = YES;
    }
    return self;
}

- (void)setImageFromURL:(NSString *)urlString {
    self.imageURL = urlString;
    self.imageView.image = nil;
    if (!urlString.length) return;
    NSString *expected = urlString;
    __weak LTMediaCell *weakCell = self;
    [[LTYouTubeClient sharedClient] loadImageWithURL:urlString completion:^(UIImage *image) {
        LTMediaCell *cell = weakCell;
        if (!cell) return;
        if ([cell.imageURL isEqualToString:expected]) {
            cell.imageView.image = image;
            [cell setNeedsLayout];
        }
    }];
}

@end
