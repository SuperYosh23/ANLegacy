#import <UIKit/UIKit.h>

// Runs the wireless desktop sync flow: starts the Bonjour-advertised HTTP
// server, shows a status alert, and reports the result. Usable from any
// view controller (playlist detail screen and app Settings).
@interface LTWirelessSync : NSObject

+ (void)beginFromViewController:(UIViewController *)presenter;

@end
