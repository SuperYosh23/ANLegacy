#import <UIKit/UIKit.h>

@protocol LTCoverPickerDelegate <NSObject>
- (void)coverPicker:(id)picker didSelectImage:(UIImage *)image;
- (void)coverPickerDidCancel:(id)picker;
@end

@interface LTCoverPickerViewController : UIViewController
@property (nonatomic, weak) id<LTCoverPickerDelegate> delegate;
+ (void)presentFromViewController:(UIViewController *)viewController delegate:(id<LTCoverPickerDelegate>)delegate;
@end
