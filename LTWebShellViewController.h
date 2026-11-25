#import <UIKit/UIKit.h>

// Hosts the web app.
//
// The whole app becomes this when a modern theme is chosen. The web app is
// served from an embedded HTTP server on the loopback interface, so it runs
// unmodified - same bundle, same localStorage, same fetch calls as the desktop
// app.
@interface LTWebShellViewController : UIViewController

// Light or dark. Applied before the first paint, so there is no flash of the
// wrong theme on launch.
@property (nonatomic, assign) BOOL darkAppearance;

@end
