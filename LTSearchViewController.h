#import <UIKit/UIKit.h>

@interface LTSearchViewController : UIViewController <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSString *type;

- (id)initWithType:(NSString *)type;

@end
