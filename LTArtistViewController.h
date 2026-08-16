#import <UIKit/UIKit.h>

@interface LTArtistViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (id)initWithBrowseId:(NSString *)browseId title:(NSString *)title;

@end
