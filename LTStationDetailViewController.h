#import <UIKit/UIKit.h>
#import "LTModel.h"

@interface LTStationDetailViewController : UIViewController

@property (nonatomic, strong, readonly) LTStation *station;

- (id)initWithStation:(LTStation *)station;

@end
