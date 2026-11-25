#import <UIKit/UIKit.h>
#import "LTModel.h"

@interface LTLocalPlaylistDetailViewController : UIViewController

@property (nonatomic, strong, readonly) LTLocalPlaylist *playlist;
@property (nonatomic, readonly) BOOL isSmartPlaylist;

- (id)initWithPlaylist:(LTLocalPlaylist *)playlist;
- (id)initWithSmartIndex:(NSInteger)index name:(NSString *)name;

@end
