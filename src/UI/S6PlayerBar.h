#import <UIKit/UIKit.h>

// The strip along the bottom that is always there: the song, its controls and progress. On the iPad the full set
// (shuffle, repeat, the heart, the queue, lyrics, volume); on the iPhone a compact one. A tap on the song opens
// the full player.
@interface S6PlayerBar : UIView
- (instancetype)initWithFrame:(CGRect)frame compact:(BOOL)compact;
+ (CGFloat)heightCompact:(BOOL)compact;
@property (nonatomic) CGFloat bottomInset;   // the home indicator of iOS 11+ under the bar (the bar's background covers it, the controls stay above)
@end
