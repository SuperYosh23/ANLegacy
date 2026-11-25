#import <UIKit/UIKit.h>

@interface LTHeaderView : UIView

- (id)initWithWidth:(CGFloat)width;

@property (nonatomic, strong) UIImageView *artworkView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;

- (void)setArtworkURL:(NSString *)urlString;

// Actions row under the subtitle. Hidden until at least one block is set, in
// which case the header grows to fit. Used by the artist page for Play All and
// Shuffle All.
@property (nonatomic, strong) UIButton *playAllButton;
@property (nonatomic, strong) UIButton *shuffleAllButton;

// Called when either action button is tapped. `shuffled` is YES for shuffle.
@property (nonatomic, copy) void (^onAction)(BOOL shuffled);

- (void)configurePlayAllTitle:(NSString *)playTitle shuffleTitle:(NSString *)shuffleTitle;

@end
