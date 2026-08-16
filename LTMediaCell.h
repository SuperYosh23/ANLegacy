#import <UIKit/UIKit.h>

@interface LTMediaCell : UITableViewCell

@property (nonatomic, copy) NSString *imageURL;

- (void)setImageFromURL:(NSString *)urlString;

@end
