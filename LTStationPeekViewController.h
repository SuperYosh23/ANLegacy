#import <UIKit/UIKit.h>

@class LTStation;

@interface LTStationPeekViewController : UIViewController

- (instancetype)initWithStation:(LTStation *)station;

@property (nonatomic, strong, readonly) LTStation *station;

@end
