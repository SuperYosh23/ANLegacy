#import <UIKit/UIKit.h>

// iOS 8 introduced -[UIViewController traitCollectionDidChange:]. Older SDKs
// (iOS 4/5/6) don't declare it, so declare it here. This lets subclasses call
// the superclass implementation via objc_msgSendSuper ([super ...]) instead of
// the broken `[super performSelector:...]` pattern, which dispatches on `self`
// and therefore re-enters the subclass override (infinite recursion).
@interface UIViewController (LTTraitCompat)
- (void)traitCollectionDidChange:(id)previousTraitCollection;
@end
