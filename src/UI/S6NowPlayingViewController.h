#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, S6NowPlayingPanel) {
    S6NowPlayingArt = 0,
    S6NowPlayingLyrics,
    S6NowPlayingQueue,
};

// The full player: the cover big over its own darkened copy, the song and artist, the heart, progress, the controls,
// and in place of the cover the synced lyrics or the queue
@interface S6NowPlayingViewController : UIViewController
@property (nonatomic) S6NowPlayingPanel panel;
@end

// The queue: now playing, "Next in queue" (removable), "Next from <context>"
@interface S6QueueViewController : UITableViewController
@end
