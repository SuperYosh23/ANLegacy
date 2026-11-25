#import <UIKit/UIKit.h>
#import "LTModel.h"

@class LTSeedSearchViewController;
@protocol LTSeedSearchViewControllerDelegate <NSObject>
- (void)seedSearchViewController:(LTSeedSearchViewController *)controller didSelectSeed:(LTStationSeed *)seed;
@end

@interface LTSeedSearchViewController : UIViewController

@property (nonatomic, unsafe_unretained) id<LTSeedSearchViewControllerDelegate> delegate;

- (id)initWithSeedType:(NSString *)seedType; // "track", "artist", or "album"

@end
