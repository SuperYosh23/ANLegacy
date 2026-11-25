#import <UIKit/UIKit.h>

// The sheet of paper the lyrics sit on.
//
// The app draws its own surfaces rather than using the system's, so on the
// systems whose own chrome was skeuomorphic - iOS 6 and earlier, where the
// grouped tables had a woven background and the rows were raised cards - the
// surfaces the app draws have to match. The lyrics get a sheet of paper: a
// warm, lightly textured card with a hairline edge and a shadow, the way a
// grouped table's rows looked.
//
// The texture is a pattern rather than a bitmap, so it stays sharp at any
// size and costs nothing in the bundle.
@interface LTLyricsPaperView : UIView

@end
