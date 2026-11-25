#import <UIKit/UIKit.h>

@protocol LTCustomActionSheetDelegate <NSObject>
- (void)customActionSheet:(id)sheet tappedButtonAtIndex:(NSInteger)index;
@end

@interface LTCustomActionSheet : UIView
@property (nonatomic, unsafe_unretained) id<LTCustomActionSheetDelegate> delegate;
- (instancetype)initWithTitle:(NSString *)title
                buttonTitles:(NSArray *)buttonTitles
             destructiveIndex:(NSInteger)destructiveIndex;
- (void)show;
@end
