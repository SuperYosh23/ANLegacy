#import <UIKit/UIKit.h>

@class LTTrack;

// Every song on an artist, in play-count order.
//
// Opened from the artist page's "Show All". Takes the list as given - the
// sorting is the client's job, done once when the artist page loaded, so
// scrolling a long list costs nothing.
@interface LTArtistSongsViewController : UIViewController

- (id)initWithArtistName:(NSString *)artistName songs:(NSArray *)songs;

@end