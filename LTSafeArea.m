#import "LTSafeArea.h"

UIEdgeInsets LTSafeAreaInsets(UIView *view) {
#if defined(__IPHONE_11_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if (@available(iOS 11.0, *)) {
        if (view) return view.safeAreaInsets;
    }
#endif
    return UIEdgeInsetsZero;
}

CGFloat LTSafeAreaTop(UIView *view) {
    return LTSafeAreaInsets(view).top;
}

CGFloat LTSafeAreaBottom(UIView *view) {
    return LTSafeAreaInsets(view).bottom;
}
