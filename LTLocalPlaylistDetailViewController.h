#import <UIKit/UIKit.h>
#import "LTModel.h"

@interface LTLocalPlaylistDetailViewController : UIViewController

@property (nonatomic, strong, readonly) LTLocalPlaylist *playlist;

- (id)initWithPlaylist:(LTLocalPlaylist *)playlist;

@end
