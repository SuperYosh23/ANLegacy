#import <UIKit/UIKit.h>

@interface LTHeaderView : UIView

- (id)initWithWidth:(CGFloat)width;

@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

- (void)setArtworkURL:(NSString *)urlString;

@end
