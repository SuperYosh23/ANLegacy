#import <UIKit/UIKit.h>
#import "LTModel.h"

typedef void (^LTPlaylistSelectCompletion)(NSArray *selectedIdentifiers, BOOL cancelled);

@interface LTPlaylistSelectViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

// Creates and returns a modally-presentable picker. Defaults all playlists to selected.
- (instancetype)initWithPlaylists:(NSArray *)playlists
                       completion:(LTPlaylistSelectCompletion)completion;

@property (nonatomic, strong, readonly) NSArray *playlists;

@end
