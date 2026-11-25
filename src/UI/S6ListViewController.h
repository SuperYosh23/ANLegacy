#import <UIKit/UIKit.h>

// The common ground of the list screens: the dark table, a spinner while loading, a message when there is nothing
// (or an error) with a "Try again" button, pull to refresh, the rows redrawn when the song changes.
@interface S6ListViewController : UITableViewController

- (instancetype)initWithStyle:(UITableViewStyle)style;

- (void)load;                                       // override: fetch, then -finishLoading...
- (void)reload;                                     // pull to refresh, "Try again"
- (void)startLoading;
- (void)finishLoadingWithError:(NSError *)error empty:(BOOL)empty emptyMessage:(NSString *)message;

@property (nonatomic) BOOL refreshable;             // pull to refresh (default YES)
@property (nonatomic, readonly) BOOL loading;

@end
