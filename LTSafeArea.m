#import "LTSafeArea.h"

#import <objc/message.h>

UIEdgeInsets LTSafeAreaInsets(UIView *view) {
    if (view && [view respondsToSelector:@selector(safeAreaInsets)]) {
        UIEdgeInsets (*fn)(id, SEL) = (UIEdgeInsets (*)(id, SEL))objc_msgSend;
        return fn(view, @selector(safeAreaInsets));
    }
    return UIEdgeInsetsZero;
}

CGFloat LTSafeAreaTop(UIView *view) {
    return LTSafeAreaInsets(view).top;
}

CGFloat LTSafeAreaBottom(UIView *view) {
    return LTSafeAreaInsets(view).bottom;
}
