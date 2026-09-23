#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

// Safe-area insets for notched devices (iPhone X and newer). The armv7 build is
// compiled against the iOS 9.3 SDK where these APIs do not exist, so the helper
// compiles to zero insets there (32-bit devices are never notched).
UIEdgeInsets LTSafeAreaInsets(UIView *view);
CGFloat LTSafeAreaTop(UIView *view);
CGFloat LTSafeAreaBottom(UIView *view);

#ifdef __cplusplus
}
#endif
