#import <UIKit/UIKit.h>
#import "LTModel.h"

@interface LTSmartPlaylistDetailViewController : UIViewController

// Preferred initializer (recommendation-based). Tracks are fetched lazily
// from the user's listening history + YouTube Music radio.
- (id)initWithSmartIndex:(NSInteger)index name:(NSString *)name;

// Legacy initializer (kept for compatibility). If tracks are supplied they
// are used as seeds for recommendations; if nil/empty, history is used.
- (id)initWithName:(NSString *)name tracks:(NSArray *)tracks;
+ (NSArray *)smartPlaylistNames;
+ (NSString *)smartPlaylistDescriptionForIndex:(NSInteger)index;

@end
