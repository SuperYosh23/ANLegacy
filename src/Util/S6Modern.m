// S6Modern.m - see S6Modern.h. Shared by all of samcejko's iOS 6 apps (only the prefix differs).
//
// Compiled twice: with the iOS 9.3 SDK for the armv7 build (deployment target iOS 6.0) and with the iOS 16.5 SDK
// for the arm64 build (deployment target iOS 14.0). APIs newer than a SDK are behind __IPHONE_OS_VERSION_MAX_ALLOWED,
// APIs newer than the running iOS behind version checks; so this file opts out of the availability errors of the
// app's common header (which it does not import) and of the deprecation warnings of the iOS 6 era APIs it bridges.
#import "S6Modern.h"
#import <objc/message.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wunguarded-availability"
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wunknown-pragmas"

#pragma mark - Versions

static NSInteger S6MajorVersion(void)
{
    static NSInteger major = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        major = [[[UIDevice currentDevice] systemVersion] integerValue];
        if (major < 1) major = 6;
    });
    return major;
}

BOOL S6ModernIOS(void) { return S6MajorVersion() >= 7; }
static BOOL S6AtLeast(NSInteger major) { return S6MajorVersion() >= major; }

#pragma mark - Safe areas

UIEdgeInsets S6SafeAreaInsets(UIView *view)
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if (view && S6AtLeast(11)) return view.safeAreaInsets;
#endif
    return UIEdgeInsetsZero;
}

UIEdgeInsets S6ScreenSafeAreaInsets(void)
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if (S6AtLeast(11)) {
        UIApplication *app = [UIApplication sharedApplication];
        UIWindow *window = app.keyWindow ?: app.windows.firstObject;
        if (window) return window.safeAreaInsets;
    }
#endif
    return UIEdgeInsetsZero;
}

UIStatusBarStyle S6ModernStatusBarStyle(UIStatusBarStyle ios6Style)
{
    // 1 is UIStatusBarStyleLightContent from iOS 7 on (UIStatusBarStyleBlackTranslucent of the iOS 6 headers)
    return S6ModernIOS() ? (UIStatusBarStyle)1 : ios6Style;
}

CGFloat S6ModernTopInset(UIView *view, CGFloat ios6Value)
{
    if (!S6ModernIOS()) return ios6Value;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if (S6AtLeast(11) && view.window) return view.safeAreaInsets.top;
#endif
    if ([UIApplication sharedApplication].statusBarHidden) return 0;
    CGRect frame = [UIApplication sharedApplication].statusBarFrame;
    return MIN(frame.size.width, frame.size.height);
}

CGFloat S6ModernGroupedCellMargins(CGFloat ios6Margins)
{
    if (!S6ModernIOS()) return ios6Margins;
    return S6AtLeast(13) ? 40 : 0;
}

#pragma mark - The iOS 6 artwork, drawn in code

static UIColor *S6RGB(NSInteger r, NSInteger g, NSInteger b)
{
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

// The colors of one glossy surface: a gradient from c1 to c2 in the upper half, a hard edge, c3 to c4 below.
typedef struct {
    NSInteger c1, c2, c3, c4;   // 0xRRGGBB
    NSInteger line;             // the border (bars: the bottom line; buttons: the outline)
    CGFloat highlight;          // alpha of the white line along the top edge
} S6Gloss;

static UIColor *S6Hex(NSInteger rgb) { return S6RGB((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff); }

static void S6DrawGloss(CGContextRef ctx, CGRect rect, S6Gloss g)
{
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat locations[4] = { 0.0, 0.5, 0.5, 1.0 };
    NSArray *colors = @[ (id)S6Hex(g.c1).CGColor, (id)S6Hex(g.c2).CGColor, (id)S6Hex(g.c3).CGColor, (id)S6Hex(g.c4).CGColor ];
    CGGradientRef gradient = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect)),
                                CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect)), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(cs);
}

// Bars (navigation bar, toolbar, search bar background): the iOS 6 blue, or the black of UIBarStyleBlack
static S6Gloss S6BarGloss(BOOL black)
{
    S6Gloss blue = { 0xb0bccd, 0x889bb3, 0x8195af, 0x6d84a2, 0x2d3642, 0.35 };
    S6Gloss dark = { 0x4d4d4d, 0x2e2e2e, 0x262626, 0x141414, 0x000000, 0.18 };
    return black ? dark : blue;
}

// A bar background. `above` is the height of the status bar the bar extends under on iOS 7 and newer (the iOS 6
// status bar took the tint of the bar below it, so that part is drawn as a lighter gradient of the same color).
static UIImage *S6BarImage(BOOL black, CGFloat above, CGFloat height)
{
    S6Gloss g = S6BarGloss(black);
    CGSize size = CGSizeMake(2, above + height);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (above > 0) {
        S6Gloss status = g;
        status.c2 = status.c1;
        status.c3 = status.c1;
        status.c4 = g.c2;
        S6DrawGloss(ctx, CGRectMake(0, 0, size.width, above), status);
    }
    S6DrawGloss(ctx, CGRectMake(0, above, size.width, height), g);
    [[UIColor colorWithWhite:1.0 alpha:g.highlight] setFill];
    UIRectFillUsingBlendMode(CGRectMake(0, above, size.width, 1), kCGBlendModeNormal);
    [S6Hex(g.line) setFill];
    UIRectFill(CGRectMake(0, size.height - 1, size.width, 1));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(1, 0, 1, 0) resizingMode:UIImageResizingModeStretch];
}

// Bordered bar buttons: normal, pressed and the blue "Done" style, on the blue or the black bar
static S6Gloss S6ButtonGloss(BOOL black, BOOL highlighted, BOOL done)
{
    if (done) {
        S6Gloss d = { 0x6aa0e6, 0x3c7cd8, 0x3374d4, 0x2563c6, 0x1d478a, 0.4 };
        S6Gloss dh = { 0x4e7fc4, 0x2a62b8, 0x235bb4, 0x184ea6, 0x15397a, 0.2 };
        return highlighted ? dh : d;
    }
    if (black) {
        S6Gloss b = { 0x6e6e6e, 0x4b4b4b, 0x434343, 0x333333, 0x0b0b0b, 0.25 };
        S6Gloss bh = { 0x4a4a4a, 0x303030, 0x2a2a2a, 0x1e1e1e, 0x050505, 0.1 };
        return highlighted ? bh : b;
    }
    S6Gloss n = { 0x8fa4c4, 0x748cb1, 0x6d86ad, 0x5f79a3, 0x3b4b62, 0.4 };
    S6Gloss nh = { 0x62789a, 0x4e6488, 0x485f84, 0x3f567c, 0x2a3648, 0.2 };
    return highlighted ? nh : n;
}

// The outline of a bar button (30 pt tall): a rounded rectangle, or the iOS 6 back button with its pointed left end
static UIBezierPath *S6ButtonPath(CGRect r, BOOL back)
{
    CGFloat radius = 5.0;
    if (!back) return [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius];
    CGFloat tip = 12.0, midY = CGRectGetMidY(r);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(CGRectGetMinX(r) + tip, CGRectGetMinY(r))];
    [p addLineToPoint:CGPointMake(CGRectGetMaxX(r) - radius, CGRectGetMinY(r))];
    [p addArcWithCenter:CGPointMake(CGRectGetMaxX(r) - radius, CGRectGetMinY(r) + radius) radius:radius startAngle:-M_PI_2 endAngle:0 clockwise:YES];
    [p addLineToPoint:CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r) - radius)];
    [p addArcWithCenter:CGPointMake(CGRectGetMaxX(r) - radius, CGRectGetMaxY(r) - radius) radius:radius startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + tip, CGRectGetMaxY(r))];
    [p addLineToPoint:CGPointMake(CGRectGetMinX(r) + 1.5, midY + 1.5)];
    [p addQuadCurveToPoint:CGPointMake(CGRectGetMinX(r) + 1.5, midY - 1.5) controlPoint:CGPointMake(CGRectGetMinX(r), midY)];
    [p closePath];
    return p;
}

static UIImage *S6ButtonImage(BOOL black, BOOL highlighted, BOOL done, BOOL back)
{
    S6Gloss g = S6ButtonGloss(black, highlighted, done);
    CGSize size = CGSizeMake(back ? 28 : 14, 30);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect inner = CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5, 0.5);
    UIBezierPath *path = S6ButtonPath(inner, back);
    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, path.CGPath);
    CGContextClip(ctx);
    S6DrawGloss(ctx, CGRectMake(0, 0, size.width, size.height), g);
    [[UIColor colorWithWhite:1.0 alpha:g.highlight] setFill];
    UIRectFillUsingBlendMode(CGRectMake(0, 1, size.width, 1), kCGBlendModeNormal);
    CGContextRestoreGState(ctx);
    [S6Hex(g.line) setStroke];
    path.lineWidth = 1.0;
    [path stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    UIEdgeInsets caps = back ? UIEdgeInsetsMake(7, 15, 7, 6) : UIEdgeInsetsMake(7, 6, 7, 6);
    return [image resizableImageWithCapInsets:caps resizingMode:UIImageResizingModeStretch];
}

// A fully transparent image (hides the iOS 7 back chevron: the pointed button background draws the arrow)
static UIImage *S6ClearImage(CGSize size)
{
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// The white rounded text field of the iOS 6 search bar
static UIImage *S6SearchFieldImage(void)
{
    CGSize size = CGSizeMake(30, 30);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5, 0.5) cornerRadius:14.5];
    [[UIColor whiteColor] setFill];
    [path fill];
    [[UIColor colorWithWhite:0.0 alpha:0.35] setStroke];
    path.lineWidth = 1.0;
    [path stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(14, 14, 14, 14) resizingMode:UIImageResizingModeStretch];
}

// The black iOS 6 tab bar, and the darker rounded area behind its selected item
static UIImage *S6TabBarImage(void)
{
    S6Gloss g = { 0x484848, 0x2a2a2a, 0x202020, 0x0a0a0a, 0x000000, 0.2 };
    CGSize size = CGSizeMake(2, 49);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    S6DrawGloss(UIGraphicsGetCurrentContext(), CGRectMake(0, 0, size.width, size.height), g);
    [[UIColor colorWithWhite:1.0 alpha:g.highlight] setFill];
    UIRectFillUsingBlendMode(CGRectMake(0, 0, size.width, 1), kCGBlendModeNormal);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(1, 0, 1, 0) resizingMode:UIImageResizingModeStretch];
}

static UIImage *S6TabSelectionImage(void)
{
    CGSize size = CGSizeMake(64, 49);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 3, size.width - 4, size.height - 6) cornerRadius:5];
    [[UIColor colorWithWhite:1.0 alpha:0.14] setFill];
    [path fill];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(10, 10, 10, 10) resizingMode:UIImageResizingModeStretch];
}

// Segments of a plain segmented control: light gray, the selected one darker
static UIImage *S6SegmentImage(BOOL selected)
{
    S6Gloss normal = { 0xfbfbfb, 0xe6e6e6, 0xdcdcdc, 0xc9c9c9, 0x8e8e8e, 0.0 };
    S6Gloss sel = { 0x9c9c9c, 0x7a7a7a, 0x717171, 0x5e5e5e, 0x4a4a4a, 0.15 };
    S6Gloss g = selected ? sel : normal;
    CGSize size = CGSizeMake(14, 32);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect inner = CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5, 0.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:5];
    CGContextSaveGState(ctx);
    CGContextAddPath(ctx, path.CGPath);
    CGContextClip(ctx);
    S6DrawGloss(ctx, CGRectMake(0, 0, size.width, size.height), g);
    if (g.highlight > 0) {
        [[UIColor colorWithWhite:1.0 alpha:g.highlight] setFill];
        UIRectFillUsingBlendMode(CGRectMake(0, 1, size.width, 1), kCGBlendModeNormal);
    }
    CGContextRestoreGState(ctx);
    [S6Hex(g.line) setStroke];
    path.lineWidth = 1.0;
    [path stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(7, 6, 7, 6) resizingMode:UIImageResizingModeStretch];
}

static UIImage *S6SegmentDividerImage(void)
{
    CGSize size = CGSizeMake(1, 32);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    [S6Hex(0x8e8e8e) setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

#pragma mark - Text styles

// White, bold, with the dark shadow above the glyphs that iOS 6 gave bar titles and bar buttons
static NSDictionary *S6EmbossedTextAttributes(CGFloat fontSize)
{
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.5];
    shadow.shadowOffset = CGSizeMake(0, -1);
    return @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:fontSize],
              NSForegroundColorAttributeName: [UIColor whiteColor],
              NSShadowAttributeName: shadow };
}

static NSDictionary *S6EngravedTextAttributes(CGFloat fontSize, UIColor *color)
{
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    shadow.shadowOffset = CGSizeMake(0, 1);
    return @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:fontSize],
              NSForegroundColorAttributeName: color,
              NSShadowAttributeName: shadow };
}

#pragma mark - Bars

// The height of the status bar the navigation bar reaches under in portrait (0 when it is hidden)
static CGFloat S6StatusBarHeight(void)
{
    CGRect frame = [UIApplication sharedApplication].statusBarFrame;
    CGFloat h = MIN(frame.size.width, frame.size.height);
    if (h <= 0) h = 20;
    return h;
}

static BOOL S6IsBlack(UIBarStyle style) { return style == UIBarStyleBlack; }

// Legacy customization (iOS 7-12; also what iOS 13 and newer fall back to where no appearance object is set).
// Whatever the look, the bar is dark: UIBarStyleBlack makes the status bar's text light and the title white.
static void S6ApplyLegacyNavigationBar(UINavigationBar *bar, BOOL black)
{
    UIImage *tall = S6BarImage(black, S6StatusBarHeight(), 44);
    UIImage *compact = S6BarImage(black, 0, 32);
    [bar setBackgroundImage:tall forBarMetrics:UIBarMetricsDefault];
    [bar setBackgroundImage:compact forBarMetrics:(UIBarMetrics)1];   // UIBarMetricsCompact (landscape iPhone)
    [bar setShadowImage:S6ClearImage(CGSizeMake(1, 1))];
    if ([bar respondsToSelector:@selector(setTitleTextAttributes:)]) [bar setTitleTextAttributes:S6EmbossedTextAttributes(20)];
    if ([(bar) respondsToSelector:@selector(setTintColor:)]) [(id)(bar) performSelector:@selector(setTintColor:) withObject:[UIColor whiteColor]];
    [bar setBarStyle:UIBarStyleBlack];
    if ([bar respondsToSelector:@selector(setBackIndicatorImage:)]) {
        if ([bar respondsToSelector:@selector(setBackIndicatorImage:)]) [bar performSelector:@selector(setBackIndicatorImage:) withObject:S6ClearImage(CGSizeMake(1, 20))];
        if ([bar respondsToSelector:@selector(setBackIndicatorTransitionMaskImage:)]) [bar performSelector:@selector(setBackIndicatorTransitionMaskImage:) withObject:S6ClearImage(CGSizeMake(1, 20))];
    }
}

static void S6ApplyLegacyBarButtons(UIBarButtonItem *proxy, BOOL black)
{
    for (int metrics = 0; metrics < 2; metrics++) {
        [proxy setBackgroundImage:S6ButtonImage(black, NO, NO, NO) forState:UIControlStateNormal barMetrics:(UIBarMetrics)metrics];
        [proxy setBackgroundImage:S6ButtonImage(black, YES, NO, NO) forState:UIControlStateHighlighted barMetrics:(UIBarMetrics)metrics];
        [proxy setBackgroundImage:S6ButtonImage(black, NO, YES, NO) forState:UIControlStateNormal style:UIBarButtonItemStyleDone barMetrics:(UIBarMetrics)metrics];
        [proxy setBackgroundImage:S6ButtonImage(black, YES, YES, NO) forState:UIControlStateHighlighted style:UIBarButtonItemStyleDone barMetrics:(UIBarMetrics)metrics];
        [proxy setBackButtonBackgroundImage:S6ButtonImage(black, NO, NO, YES) forState:UIControlStateNormal barMetrics:(UIBarMetrics)metrics];
        [proxy setBackButtonBackgroundImage:S6ButtonImage(black, YES, NO, YES) forState:UIControlStateHighlighted barMetrics:(UIBarMetrics)metrics];
        [proxy setBackButtonTitlePositionAdjustment:UIOffsetMake(6, 0) forBarMetrics:(UIBarMetrics)metrics];
    }
    if ([proxy respondsToSelector:@selector(setTitleTextAttributes:forState:)]) [proxy setTitleTextAttributes:S6EmbossedTextAttributes(12) forState:UIControlStateNormal];
    if ([proxy respondsToSelector:@selector(setTitleTextAttributes:forState:)]) [proxy setTitleTextAttributes:S6EmbossedTextAttributes(12) forState:UIControlStateHighlighted];
}

static void S6ApplyLegacyToolbar(UIToolbar *bar, BOOL black)
{
    if ([bar respondsToSelector:@selector(setBackgroundImage:forToolbarPosition:barMetrics:)]) { ((void(*)(id,SEL,id,NSInteger,NSInteger))objc_msgSend)(bar, @selector(setBackgroundImage:forToolbarPosition:barMetrics:), S6BarImage(black, 0, 44), 0, UIBarMetricsDefault); }
    if ([bar respondsToSelector:@selector(setBackgroundImage:forToolbarPosition:barMetrics:)]) { ((void(*)(id,SEL,id,NSInteger,NSInteger))objc_msgSend)(bar, @selector(setBackgroundImage:forToolbarPosition:barMetrics:), S6BarImage(black, 0, 32), 0, 1); }
    if ([bar respondsToSelector:@selector(setShadowImage:forToolbarPosition:)]) { ((void(*)(id,SEL,id,NSInteger))objc_msgSend)(bar, @selector(setShadowImage:forToolbarPosition:), S6ClearImage(CGSizeMake(1, 1)), 0); }
    if ([(bar) respondsToSelector:@selector(setTintColor:)]) [(id)(bar) performSelector:@selector(setTintColor:) withObject:[UIColor whiteColor]];
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
// iOS 13 and newer: the appearance objects (without them iOS 15 draws the bars transparent at the scroll edge)
static UIBarButtonItemAppearance *S6ButtonAppearance(BOOL black, BOOL done, BOOL back)
{
    UIBarButtonItemAppearance *a = [[UIBarButtonItemAppearance alloc] initWithStyle:done ? UIBarButtonItemStyleDone : UIBarButtonItemStylePlain];
    NSDictionary *text = S6EmbossedTextAttributes(12);
    a.normal.backgroundImage = S6ButtonImage(black, NO, done, back);
    a.normal.titleTextAttributes = text;
    a.highlighted.backgroundImage = S6ButtonImage(black, YES, done, back);
    a.highlighted.titleTextAttributes = text;
    a.disabled.backgroundImage = a.normal.backgroundImage;
    a.disabled.titleTextAttributes = @{ NSFontAttributeName: [UIFont boldSystemFontOfSize:12], NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.5] };
    if (back) {
        a.normal.titlePositionAdjustment = UIOffsetMake(6, 0);
        a.highlighted.titlePositionAdjustment = UIOffsetMake(6, 0);
        a.disabled.titlePositionAdjustment = UIOffsetMake(6, 0);
    }
    return a;
}

static UINavigationBarAppearance *S6NavigationBarAppearance(BOOL black, BOOL compact)
{
    UINavigationBarAppearance *a = [[UINavigationBarAppearance alloc] init];
    [a configureWithOpaqueBackground];
    a.backgroundImage = compact ? S6BarImage(black, 0, 32) : S6BarImage(black, S6StatusBarHeight(), 44);
    a.backgroundImageContentMode = UIViewContentModeScaleToFill;
    a.shadowColor = nil;
    a.shadowImage = nil;
    a.titleTextAttributes = S6EmbossedTextAttributes(compact ? 17 : 20);
    a.largeTitleTextAttributes = S6EmbossedTextAttributes(34);
    a.buttonAppearance = S6ButtonAppearance(black, NO, NO);
    a.doneButtonAppearance = S6ButtonAppearance(black, YES, NO);
    a.backButtonAppearance = S6ButtonAppearance(black, NO, YES);
    [a setBackIndicatorImage:S6ClearImage(CGSizeMake(1, 20)) transitionMaskImage:S6ClearImage(CGSizeMake(1, 20))];
    return a;
}

static void S6SetNavigationBarAppearances(UINavigationBar *bar, UINavigationBarAppearance *standard, UINavigationBarAppearance *compact)
{
    [bar setStandardAppearance:standard];
    [bar setScrollEdgeAppearance:standard];
    [bar setCompactAppearance:compact];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 150000
    if (S6AtLeast(15)) [bar setCompactScrollEdgeAppearance:compact];
#endif
}

static void S6ApplyNavigationBarAppearance(UINavigationBar *bar, BOOL black)
{
    S6SetNavigationBarAppearances(bar, S6NavigationBarAppearance(black, NO), S6NavigationBarAppearance(black, YES));
    if ([(bar) respondsToSelector:@selector(setTintColor:)]) [(id)(bar) performSelector:@selector(setTintColor:) withObject:[UIColor whiteColor]];
    [bar setBarStyle:UIBarStyleBlack];
}

static UIToolbarAppearance *S6ToolbarAppearance(BOOL black, BOOL compact)
{
    UIToolbarAppearance *a = [[UIToolbarAppearance alloc] init];
    [a configureWithOpaqueBackground];
    a.backgroundImage = S6BarImage(black, 0, compact ? 32 : 44);
    a.backgroundImageContentMode = UIViewContentModeScaleToFill;
    a.shadowColor = nil;
    a.shadowImage = nil;
    return a;
}

static void S6ApplyToolbarAppearance(UIToolbar *bar, BOOL black)
{
    UIToolbarAppearance *standard = S6ToolbarAppearance(black, NO);
    UIToolbarAppearance *compact = S6ToolbarAppearance(black, YES);
    [bar setStandardAppearance:standard];
    [bar setCompactAppearance:compact];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 150000
    if (S6AtLeast(15)) {
        [bar setScrollEdgeAppearance:standard];
        [bar setCompactScrollEdgeAppearance:compact];
    }
#endif
    if ([(bar) respondsToSelector:@selector(setTintColor:)]) [(id)(bar) performSelector:@selector(setTintColor:) withObject:[UIColor whiteColor]];
}

static void S6SetTabBarAppearance(UITabBar *bar, UITabBarAppearance *a)
{
    [bar setStandardAppearance:a];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 150000
    if (S6AtLeast(15)) [bar setScrollEdgeAppearance:a];
#endif
}

static void S6ApplyTabBarAppearance(UITabBar *bar)
{
    UITabBarAppearance *a = [[UITabBarAppearance alloc] init];
    [a configureWithOpaqueBackground];
    a.backgroundImage = S6TabBarImage();
    a.shadowColor = nil;
    a.shadowImage = nil;
    a.selectionIndicatorImage = S6TabSelectionImage();
    UIColor *selected = S6RGB(84, 164, 255), *normal = S6RGB(146, 146, 146);
    for (UITabBarItemAppearance *item in @[ a.stackedLayoutAppearance, a.inlineLayoutAppearance, a.compactInlineLayoutAppearance ]) {
        item.selected.iconColor = selected;
        item.selected.titleTextAttributes = @{ NSForegroundColorAttributeName: selected, NSFontAttributeName: [UIFont boldSystemFontOfSize:10] };
        item.normal.iconColor = normal;
        item.normal.titleTextAttributes = @{ NSForegroundColorAttributeName: normal, NSFontAttributeName: [UIFont boldSystemFontOfSize:10] };
    }
    S6SetTabBarAppearance(bar, a);
    if ([(bar) respondsToSelector:@selector(setTintColor:)]) [(id)(bar) performSelector:@selector(setTintColor:) withObject:selected];
}
#endif

void S6ModernApplyNavigationBarBackground(UINavigationBar *bar, UIImage *image, NSDictionary *titleAttributes,
                                             UIImage *buttonImage, UIImage *buttonImageHighlighted, NSDictionary *buttonTitleAttributes)
{
    if (!bar || !image || !S6ModernIOS()) return;
    if ([bar respondsToSelector:@selector(setTranslucent:)]) { BOOL _no = NO; NSInvocation *_inv = [NSInvocation invocationWithMethodSignature:[(id)bar methodSignatureForSelector:@selector(setTranslucent:)]]; [_inv setSelector:@selector(setTranslucent:)]; [_inv setTarget:bar]; [_inv setArgument:&_no atIndex:2]; [_inv invoke]; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) {
        UINavigationBarAppearance *a = [[UINavigationBarAppearance alloc] init];
        [a configureWithOpaqueBackground];
        a.backgroundImage = image;
        a.backgroundImageContentMode = UIViewContentModeScaleToFill;
        a.shadowColor = nil;
        a.shadowImage = nil;
        if (titleAttributes) a.titleTextAttributes = titleAttributes;
        if (buttonImage || buttonTitleAttributes) {
            for (UIBarButtonItemAppearance *b in @[ a.buttonAppearance, a.doneButtonAppearance, a.backButtonAppearance ]) {
                if (buttonImage) {
                    b.normal.backgroundImage = buttonImage;
                    b.highlighted.backgroundImage = buttonImageHighlighted ?: buttonImage;
                    b.disabled.backgroundImage = buttonImage;
                }
                if (buttonTitleAttributes) {
                    b.normal.titleTextAttributes = buttonTitleAttributes;
                    b.highlighted.titleTextAttributes = buttonTitleAttributes;
                }
            }
        }
        S6SetNavigationBarAppearances(bar, a, a);
        return;
    }
#endif
    [bar setBackgroundImage:image forBarMetrics:UIBarMetricsDefault];
    [bar setBackgroundImage:image forBarMetrics:(UIBarMetrics)1];
    [bar setShadowImage:S6ClearImage(CGSizeMake(1, 1))];
    if (titleAttributes && [bar respondsToSelector:@selector(setTitleTextAttributes:)]) [bar setTitleTextAttributes:titleAttributes];
    // (the legacy button images come from the app's own UIBarButtonItem appearance; nothing more to do here)
}

UITextField *S6ModernSearchBarTextField(UISearchBar *bar)
{
    if (!bar) return nil;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13) && [bar respondsToSelector:@selector(searchTextField)]) {
        return (UITextField *)[bar performSelector:@selector(searchTextField)];
    }
#endif
    NSMutableArray *queue = [NSMutableArray arrayWithObject:bar];
    while (queue.count) {
        UIView *v = ([queue count] ? [queue objectAtIndex:0] : nil);
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:[UITextField class]]) return (UITextField *)v;
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

void S6ModernApplyTabBarBackground(UITabBar *bar, UIImage *image)
{
    if (!bar || !image || !S6ModernIOS()) return;
    if ([bar respondsToSelector:@selector(setTranslucent:)]) { BOOL _no = NO; NSInvocation *_inv = [NSInvocation invocationWithMethodSignature:[(id)bar methodSignatureForSelector:@selector(setTranslucent:)]]; [_inv setSelector:@selector(setTranslucent:)]; [_inv setTarget:bar]; [_inv setArgument:&_no atIndex:2]; [_inv invoke]; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) {
        UITabBarAppearance *a = [[UITabBarAppearance alloc] init];
        [a configureWithOpaqueBackground];
        a.backgroundImage = image;
        a.shadowColor = nil;
        a.shadowImage = nil;
        S6SetTabBarAppearance(bar, a);
        return;
    }
#endif
    [bar setBackgroundImage:image];
    [bar setShadowImage:S6ClearImage(CGSizeMake(1, 1))];
}

void S6ModernKeepScrollViewInsets(UIScrollView *scrollView)
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if (scrollView && S6AtLeast(11)) scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
#endif
}

void S6ModernDisableSwipeBack(UINavigationController *nav)
{
    if (nav && [nav respondsToSelector:@selector(interactivePopGestureRecognizer)]) ((id(*)(id,SEL))objc_msgSend)(nav, @selector(interactivePopGestureRecognizer)); if ([nav respondsToSelector:@selector(interactivePopGestureRecognizer)]) { id _gr = [nav performSelector:@selector(interactivePopGestureRecognizer)]; if ([_gr respondsToSelector:@selector(setEnabled:)]) { BOOL _no = NO; [_gr setValue:@(_no) forKey:@"enabled"]; } }
}

void S6ModernStatusBarChanged(UIViewController *vc)
{
    if (vc && [vc respondsToSelector:@selector(setNeedsStatusBarAppearanceUpdate)]) [(id)vc performSelector:@selector(setNeedsStatusBarAppearanceUpdate)];
}

void S6ModernStyleNavigationBar(UINavigationBar *bar)
{
    if (!bar || !S6ModernIOS()) return;
    BOOL black = S6IsBlack(bar.barStyle);
    if ([bar respondsToSelector:@selector(setTranslucent:)]) { BOOL _no = NO; NSInvocation *_inv = [NSInvocation invocationWithMethodSignature:[(id)bar methodSignatureForSelector:@selector(setTranslucent:)]]; [_inv setSelector:@selector(setTranslucent:)]; [_inv setTarget:bar]; [_inv setArgument:&_no atIndex:2]; [_inv invoke]; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) { S6ApplyNavigationBarAppearance(bar, black); return; }
#endif
    S6ApplyLegacyNavigationBar(bar, black);
}

void S6ModernStyleToolbar(UIToolbar *bar)
{
    if (!bar || !S6ModernIOS()) return;
    BOOL black = S6IsBlack(bar.barStyle);
    if ([bar respondsToSelector:@selector(setTranslucent:)]) { BOOL _no = NO; NSInvocation *_inv = [NSInvocation invocationWithMethodSignature:[(id)bar methodSignatureForSelector:@selector(setTranslucent:)]]; [_inv setSelector:@selector(setTranslucent:)]; [_inv setTarget:bar]; [_inv setArgument:&_no atIndex:2]; [_inv invoke]; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) { S6ApplyToolbarAppearance(bar, black); return; }
#endif
    S6ApplyLegacyToolbar(bar, black);
}

void S6ModernStyleSearchBar(UISearchBar *bar)
{
    if (!bar || !S6ModernIOS()) return;
    BOOL black = S6IsBlack(bar.barStyle);
    if ([bar respondsToSelector:@selector(setTranslucent:)]) [(id)bar setTranslucent:NO];
    [bar setBackgroundImage:S6BarImage(black, 0, 44)];
    [bar setSearchFieldBackgroundImage:S6SearchFieldImage() forState:UIControlStateNormal];
    [bar setSearchTextPositionAdjustment:UIOffsetMake(4, 0)];
    if ([bar respondsToSelector:@selector(setTintColor:)]) [(id)bar setTintColor:[UIColor whiteColor]];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) {
        UITextField *tf = S6ModernSearchBarTextField(bar);
        if (tf && [tf respondsToSelector:@selector(setTintColor:)]) [(id)tf setTintColor:S6RGB(30, 90, 200)];
        if (tf && [tf respondsToSelector:@selector(setTextColor:)]) [tf setTextColor:[UIColor blackColor]];
    }
#endif
}

void S6ModernStyleTabBar(UITabBar *bar)
{
    if (!bar || !S6ModernIOS()) return;
    if ([bar respondsToSelector:@selector(setTranslucent:)]) { BOOL _no = NO; NSInvocation *_inv = [NSInvocation invocationWithMethodSignature:[(id)bar methodSignatureForSelector:@selector(setTranslucent:)]]; [_inv setSelector:@selector(setTranslucent:)]; [_inv setTarget:bar]; [_inv setArgument:&_no atIndex:2]; [_inv invoke]; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) { S6ApplyTabBarAppearance(bar); return; }
#endif
    [bar setBackgroundImage:S6TabBarImage()];
    [bar setSelectionIndicatorImage:S6TabSelectionImage()];
    [bar setShadowImage:S6ClearImage(CGSizeMake(1, 1))];
    if ([(bar) respondsToSelector:@selector(setTintColor:)]) [(id)(bar) performSelector:@selector(setTintColor:) withObject:S6RGB(84, 164, 255)];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 100000
    if ([bar respondsToSelector:@selector(setUnselectedItemTintColor:)]) [bar setUnselectedItemTintColor:S6RGB(146, 146, 146)];
#endif
}

#pragma mark - The defaults for every bar (UIAppearance)

static id S6AppearanceInside(Class cls, Class container)
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
    if ([(id)cls respondsToSelector:@selector(appearanceWhenContainedInInstancesOfClasses:)]) {
        return [cls appearanceWhenContainedInInstancesOfClasses:@[ container ]];
    }
#endif
    return [cls appearanceWhenContainedIn:container, nil];
}

// full-width separators, as before iOS 7
static void S6InstallTableDefaults(void)
{
    id _tvApp = [UITableView appearance]; if ([_tvApp respondsToSelector:@selector(setSeparatorInset:)]) ((void(*)(id,SEL,UIEdgeInsets))objc_msgSend)(_tvApp, @selector(setSeparatorInset:), UIEdgeInsetsZero);
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
    if ([[UITableView appearance] respondsToSelector:@selector(setCellLayoutMarginsFollowReadableWidth:)]) {
        [[UITableView appearance] setCellLayoutMarginsFollowReadableWidth:NO];
    }
#endif
}

static void S6InstallAppearance(BOOL black)
{
    // navigation bars, toolbars, tab bars, search bars (the same artwork as the per-bar functions above)
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) {
        S6ApplyNavigationBarAppearance([UINavigationBar appearance], black);
        S6ApplyToolbarAppearance([UIToolbar appearance], black);
        S6ApplyTabBarAppearance([UITabBar appearance]);
    } else
#endif
    {
        S6ApplyLegacyNavigationBar([UINavigationBar appearance], black);
        S6ApplyLegacyToolbar([UIToolbar appearance], black);
        [[UITabBar appearance] setBackgroundImage:S6TabBarImage()];
        [[UITabBar appearance] setSelectionIndicatorImage:S6TabSelectionImage()];
        if ([([UITabBar appearance]) respondsToSelector:@selector(setTintColor:)]) [(id)([UITabBar appearance]) performSelector:@selector(setTintColor:) withObject:S6RGB(84, 164, 255)];
    }
    [[UINavigationBar appearance] setTranslucent:NO];
    [[UIToolbar appearance] setTranslucent:NO];
    [[UITabBar appearance] setTranslucent:NO];

    // bordered bar buttons: in navigation bars (as on iOS 6, where plain items were bordered there too) and the
    // Cancel button of search bars; toolbars keep their borderless white glyphs
    S6ApplyLegacyBarButtons((UIBarButtonItem *)S6AppearanceInside([UIBarButtonItem class], [UINavigationBar class]), black);
    S6ApplyLegacyBarButtons((UIBarButtonItem *)S6AppearanceInside([UIBarButtonItem class], [UISearchBar class]), black);
    if ([[UIBarButtonItem appearance] respondsToSelector:@selector(setTitleTextAttributes:forState:)]) [[UIBarButtonItem appearance] setTitleTextAttributes:S6EmbossedTextAttributes(12) forState:UIControlStateNormal];

    [[UISearchBar appearance] setBackgroundImage:S6BarImage(black, 0, 44)];
    [[UISearchBar appearance] setSearchFieldBackgroundImage:S6SearchFieldImage() forState:UIControlStateNormal];
    [[UISearchBar appearance] setSearchTextPositionAdjustment:UIOffsetMake(4, 0)];
    { id tf = S6AppearanceInside([UITextField class], [UISearchBar class]); if ([tf respondsToSelector:@selector(setTintColor:)]) [tf performSelector:@selector(setTintColor:) withObject:S6RGB(30, 90, 200)]; }

    // the iOS 6 blue of switches; glossy gray segmented controls with engraved labels
    [[UISwitch appearance] setOnTintColor:S6RGB(26, 108, 213)];
    UISegmentedControl *segment = [UISegmentedControl appearance];
    [segment setBackgroundImage:S6SegmentImage(NO) forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [segment setBackgroundImage:S6SegmentImage(YES) forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
    [segment setBackgroundImage:S6SegmentImage(YES) forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    UIImage *divider = S6SegmentDividerImage();
    [segment setDividerImage:divider forLeftSegmentState:UIControlStateNormal rightSegmentState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [segment setDividerImage:divider forLeftSegmentState:UIControlStateSelected rightSegmentState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [segment setDividerImage:divider forLeftSegmentState:UIControlStateNormal rightSegmentState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
    if ([segment respondsToSelector:@selector(setTitleTextAttributes:forState:)]) [segment setTitleTextAttributes:S6EngravedTextAttributes(13, S6RGB(60, 60, 60)) forState:UIControlStateNormal];
    if ([segment respondsToSelector:@selector(setTitleTextAttributes:forState:)]) [segment setTitleTextAttributes:S6EmbossedTextAttributes(13) forState:UIControlStateSelected];
    S6InstallTableDefaults();
}

#pragma mark - iOS 13: full-screen modals and rounded grouped tables

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
static void (*S6OriginalPresent)(id, SEL, UIViewController *, BOOL, void (^)(void));
static id (*S6OriginalTableInit)(id, SEL, CGRect, UITableViewStyle);

// The app's own view controllers (also wrapped in a navigation or tab bar controller), not UIKit's pickers and sheets
static BOOL S6IsAppController(UIViewController *vc)
{
    UIViewController *probe = vc;
    if ([vc isKindOfClass:[UINavigationController class]]) probe = ((UINavigationController *)vc).viewControllers.firstObject ?: vc;
    else if ([vc isKindOfClass:[UITabBarController class]]) probe = ((UITabBarController *)vc).viewControllers.firstObject ?: vc;
    // (the bundle of a class from the executable is the main bundle; a system picker or sheet lives under /System)
    NSBundle *bundle = [NSBundle bundleForClass:[probe class]];
    if (bundle == [NSBundle mainBundle]) return YES;
    NSString *path = bundle.bundlePath ?: @"";
    return path.length && ![path hasPrefix:@"/System/"] && ![path hasPrefix:@"/Developer/"] && ![path hasPrefix:@"/usr/"];
}

static void S6Present(id self, SEL _cmd, UIViewController *vc, BOOL animated, void (^completion)(void))
{
    // iOS 13 made the default a card that slides up and can be dragged away; iOS 6 presented full screen
    if (vc && vc.modalPresentationStyle == UIModalPresentationAutomatic && S6IsAppController(vc)) {
        vc.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    S6OriginalPresent(self, _cmd, vc, animated, completion);
}

static id S6TableInit(id self, SEL _cmd, CGRect frame, UITableViewStyle style)
{
    // iOS 13 draws grouped tables as full-width flat lists; the inset style keeps the rounded groups of iOS 6
    if (style == UITableViewStyleGrouped) {
        self = S6OriginalTableInit(self, _cmd, frame, UITableViewStyleInsetGrouped);
        [self setBackgroundColor:S6RGB(197, 204, 212)];
        return self;
    }
    return S6OriginalTableInit(self, _cmd, frame, style);
}

static void S6InstallIOS13Behaviour(void)
{
    Method present = class_getInstanceMethod([UIViewController class], @selector(presentViewController:animated:completion:));
    if (present && !S6OriginalPresent) {
        S6OriginalPresent = (void (*)(id, SEL, UIViewController *, BOOL, void (^)(void)))method_getImplementation(present);
        method_setImplementation(present, (IMP)S6Present);
    }
    Method tableInit = class_getInstanceMethod([UITableView class], @selector(initWithFrame:style:));
    if (tableInit && !S6OriginalTableInit) {
        S6OriginalTableInit = (id (*)(id, SEL, CGRect, UITableViewStyle))method_getImplementation(tableInit);
        method_setImplementation(tableInit, (IMP)S6TableInit);
    }
}
#endif

#pragma mark - Tables

void S6ModernSetTableViewDark(UITableView *tableView, BOOL dark)
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    // (the forced light style of the app would draw dark grey section headers on a dark table)
    if (S6AtLeast(13)) tableView.overrideUserInterfaceStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
#endif
}
#pragma mark - Set-up

static BOOL S6setUpDone = NO;

void S6ModernSetUp(UIBarStyle defaultBarStyle)
{
    if (!S6ModernIOS() || S6setUpDone) return;
    S6setUpDone = YES;
    S6InstallAppearance(S6IsBlack(defaultBarStyle));
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) S6InstallIOS13Behaviour();
#endif
    NSLog(@"[S6Modern] iOS %@: the iOS 6 look is on", [UIDevice currentDevice].systemVersion);
}

void S6ModernSetUpWithoutSkin(void)
{
    if (!S6ModernIOS() || S6setUpDone) return;
    S6setUpDone = YES;
    S6InstallTableDefaults();
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (S6AtLeast(13)) S6InstallIOS13Behaviour();
#endif
    NSLog(@"[S6Modern] iOS %@: iOS 6 behaviour on (the app's own look)", [UIDevice currentDevice].systemVersion);
}

void S6ModernRequestNotificationPermission(void)
{
    UIApplication *app = [UIApplication sharedApplication];
    if (!S6AtLeast(8)) return;
    SEL regSel = NSSelectorFromString(@"registerUserNotificationSettings:");
    if (![app respondsToSelector:regSel]) return;

    Class settingsClass = NSClassFromString(@"UIUserNotificationSettings");
    SEL settingsSel = NSSelectorFromString(@"settingsForTypes:categories:");
    if (!settingsClass || ![settingsClass respondsToSelector:settingsSel]) return;

    // UIUserNotificationTypeAlert|Sound|Badge = 1|2|4 = 7
    NSUInteger types = 7;
    id settings = ((id (*)(id, SEL, NSUInteger, id))objc_msgSend)(settingsClass, settingsSel, types, nil);
    if (!settings) return;
    ((void (*)(id, SEL, id))objc_msgSend)(app, regSel, settings);
}
