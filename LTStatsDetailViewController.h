#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, LTStatsDetailType) {
    LTStatsDetailTypeTracks = 0,
    LTStatsDetailTypeArtists = 1,
};

@interface LTStatsDetailViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (id)initWithType:(LTStatsDetailType)type;
@end