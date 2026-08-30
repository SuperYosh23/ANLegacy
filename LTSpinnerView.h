#import <UIKit/UIKit.h>

@interface LTSpinnerView : UIView

@property (nonatomic, assign) CGFloat lineWidth;
@property (nonatomic, assign) BOOL hidesWhenStopped;

- (void)startAnimating;
- (void)stopAnimating;
- (BOOL)isAnimating;

@end