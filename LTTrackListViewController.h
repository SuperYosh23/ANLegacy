#import <UIKit/UIKit.h>
#import "LTModel.h"

@interface LTTrackListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

- (id)initWithBrowseId:(NSString *)browseId kind:(LTBrowseKind)kind title:(NSString *)title;

@end
