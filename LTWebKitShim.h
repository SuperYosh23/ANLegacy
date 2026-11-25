#import <UIKit/UIKit.h>

// The slice of WebKit this app uses, declared by hand.
//
// WHY: this SDK ships a stub WebKit in System/Library/PrivateFrameworks, and
// that stub sits earlier on the header search path than the public framework.
// Every angle-bracket import of WebKit - including the ones inside WebKit's own
// umbrella header - therefore resolves to the stub and fails with "file not
// found". The module map has the same problem, because the module's umbrella
// header includes the stub's neighbours.
//
// The fix is to not import WebKit at all. The four members below are stable
// since iOS 8, and the class names are the real ones, so the runtime resolves
// them to the genuine WebKit classes. The framework is weak-linked (see the
// Makefile), so on iOS 6 and 7 - where WKWebView does not exist - these class
// references resolve to nil instead of failing the launch.
//
// The modern themes are gated to iOS 9+, where WKWebView exists.

typedef NS_OPTIONS(NSInteger, LTWKAudiovisualMediaTypes) {
    LTWKAudiovisualMediaTypeNone = 0,
    LTWKAudiovisualMediaTypeAll = -1,
};

@interface WKWebViewConfiguration : NSObject
// iOS 8.
@property (nonatomic) BOOL allowsInlineMediaPlayback;
// iOS 10. Guarded at the call site: setting it on iOS 9 would be an
// unrecognised selector.
@property (nonatomic) LTWKAudiovisualMediaTypes mediaTypesRequiringUserActionForPlayback;
@end

@interface WKWebView : UIView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration;
- (void)loadRequest:(NSURLRequest *)request;
- (void)evaluateJavaScript:(NSString *)javaScriptString
         completionHandler:(void (^)(id result, NSError *error))completionHandler;
@property (nonatomic, readonly) UIScrollView *scrollView;
@end
