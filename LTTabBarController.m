#import "LTTabBarController.h"
#import "LTTheme.h"
#import "LTCardNavBar.h"
#import "LTAppTabBar.h"
#import "LTTransitionSettings.h"
#import "LTPlayerController.h"
#import "LTLog.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>

@interface LTTabBarController () <UITabBarControllerDelegate>
@property (nonatomic, strong) UIImageView *contentSnapshot;
@property (nonatomic, assign) NSInteger slideFromIndex;
@property (nonatomic, strong) UIImageView *outgoingOverlay;
@property (nonatomic, assign) NSInteger slideToIndex;
@property (nonatomic, assign) BOOL fading;
@property (nonatomic, assign) CGRect slideContentRect;
@property (nonatomic, assign) NSInteger lastAnnouncedIndex;
@property (nonatomic, assign) BOOL lastForcedHiddenState;
@property (nonatomic, assign) CGFloat lastGoodBarHeight;
@property (nonatomic, assign) CGFloat lastDebugW;
@property (nonatomic, assign) CGFloat lastDebugH;
@property (nonatomic, assign) BOOL lastDebugForced;
@end

@implementation LTTabBarController

- (instancetype)init {
    self = [super init];
    if (self) {
        // Swap in LTAppTabBar (compact trait in one-handed mode) before the
        // controller builds its default bar.
        [self setValue:[[LTAppTabBar alloc] init] forKey:@"tabBar"];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;
    self.lastAnnouncedIndex = NSNotFound;
    [self lt_applyModernChrome];
}

// Remote-control events start at the first responder and travel up the chain.
// The app delegate is not reliably in that chain on iOS 4, but this controller
// is the window's root on iPhone/iPod touch, so it is. Becoming first responder
// here makes the lock screen and wired earbuds work without opening the app.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    [[LTPlayerController sharedController] handleRemoteControlEvent:event];
}

// Puts the Material 3 navigation and tab bars in place.
//
// The navigation bar is swapped the same way the tab bar is - by replacing the
// controller's own bar before it builds one - so every push and pop, the title
// and the back button all keep working exactly as before. Only the painting
// differs.
- (void)lt_applyModernChrome {
    if (![LTTheme isModern]) return;

    // On iOS 9+ the navigation controller is created with a standard bar
    // (initWithNavigationBarClass: is unreliable there). Swapping the bar by
    // KVC after the controller has built its view does not change the bar that
    // is actually on screen, so paint the existing bar directly instead.
    BOOL styleStandardBar = [[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0f;

    for (UIViewController *controller in self.viewControllers) {
        if (![controller isKindOfClass:[UINavigationController class]]) continue;
        UINavigationController *nav = (UINavigationController *)controller;
        if (styleStandardBar) {
            [LTCardNavBar applyModernStyleToNavigationBar:nav.navigationBar];
            continue;
        }
        if ([nav.navigationBar isKindOfClass:[LTCardNavBar class]]) continue;
        [nav setValue:[[LTCardNavBar alloc] init] forKey:@"navigationBar"];
    }
}

// Dock mode: only the Now Playing tab (the last one) may rotate into landscape
// (with its dock layout). Every other screen stays locked to portrait, the way
// the app behaved before landscape was enabled. Switching tabs while landscape
// re-asks for the mask, so the app rotates itself back to portrait.
- (BOOL)shouldAutorotate {
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations {
    NSInteger playerIndex = (NSInteger)(self.viewControllers.count - 1);
    if ((NSInteger)self.selectedIndex == playerIndex) {
        return (NSUInteger)UIInterfaceOrientationMaskAll;
    }
    return (NSUInteger)UIInterfaceOrientationMaskPortrait;
}

// On the iPad the split container parks the tab bar away in landscape. Even so,
// UITabBarController keeps reserving the bar's ~49pt and lays the child short,
// leaving a dead black strip beneath the player. This re-asserts the intended
// layout on EVERY pass — collapsing the bar to zero height and pushing the
// selected child (and its hosting container) to full bounds.
- (void)hideBarAndGrowChild {
    CGRect b = self.view.bounds;
    if (b.size.width < 1.0f || b.size.height < 1.0f) return;
    self.tabBar.hidden = YES;
    self.tabBar.frame = CGRectMake(0.0f, b.size.height, b.size.width, 0.0f);
    UIViewController *sel = self.selectedViewController;
    if (sel) {
        sel.view.frame = b;
        // iOS 6 keeps a private content container (a UITransitionView) at
        // bar-reserved height even with the bar hidden, so it clips the child and
        // a black strip shows where the bar was. That short container sits higher
        // up the chain, above the child's immediate superview, so resizing just
        // that superview is not enough — walk every ancestor up to (not
        // including) the window and give it full bounds. In dock the whole chain
        // is meant to be full screen (nav bar hidden), so this is correct.
        UIView *v = sel.view.superview;
        while (v && v != sel.view.window) {
            v.frame = b;
            v = v.superview;
        }
    }
}

// Restore a bar we collapsed for dock. Without this, rotating back to portrait
// leaves the bar hidden while the container still reserves its ~49pt, a black
// strip at the bottom of portrait that never goes away.
- (void)showBar {
    CGRect b = self.view.bounds;
    if (b.size.width < 1.0f || b.size.height < 1.0f) return;
    CGFloat h = (self.lastGoodBarHeight > 0.5f) ? self.lastGoodBarHeight : 49.0f;
    if (h > b.size.height) h = b.size.height;
    self.tabBar.frame = CGRectMake(0.0f, b.size.height - h, b.size.width, h);
    self.tabBar.hidden = NO;
    [self.view setNeedsLayout];
}

- (void)assertForcedHiddenTabBarLayout {
    CGRect b = self.view.bounds;
    if (b.size.width < 1.0f || b.size.height < 1.0f) return;

    BOOL barDocked = (!self.tabBar.hidden &&
                      CGRectGetHeight(self.tabBar.frame) > 0.5f &&
                      CGRectGetMaxY(self.tabBar.frame) <= b.size.height + 0.5f &&
                      CGRectGetMaxY(self.tabBar.frame) >= b.size.height - 0.5f);
    if (barDocked) self.lastGoodBarHeight = CGRectGetHeight(self.tabBar.frame);

    BOOL isPad = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
    if (isPad) {
        // The iPad split container drives the bar; keep the legacy behavior.
        if (self.tabBarForcedHidden || !barDocked) [self hideBarAndGrowChild];
    } else if (self.tabBarForcedHidden) {
        [self hideBarAndGrowChild];
    } else if (self.tabBar.hidden) {
        [self showBar];
    }
}

// iOS 6's UITabBarController cannot release the bar's space across a rotation:
// hiding the bar either leaves the child clipped by a bar-reserved content
// container (a black strip) or, if forced, cancels the window rotation outright.
// So the landscape dock keeps the tab bar visible on phones at every OS version —
// iOS 6 needs it, and the newer phones match it for consistency. The child just
// gets the bar-reserved height and the dock lays out cleanly above the bar.
static BOOL LTPhoneDockKeepsTabBarVisible(void) {
    return ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad);
}

// Dock mode hides the tab bar while On Now Playing in landscape; anything else
// shows it. Re-derive each layout pass so it tracks rotation and tab switches.
// The iPad split container manages the bar itself, so leave it alone there.
- (void)updateForcedHiddenState {
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) return;
    NSInteger playerIndex = (NSInteger)(self.viewControllers.count - 1);
    BOOL onPlayer = ((NSInteger)self.selectedIndex == playerIndex);
    BOOL landscape = (self.view.bounds.size.width > self.view.bounds.size.height);
    BOOL shouldHide = (onPlayer && landscape) && !LTPhoneDockKeepsTabBarVisible();
    if (self.tabBarForcedHidden != shouldHide) {
        self.tabBarForcedHidden = shouldHide;
        [self.view setNeedsLayout];
    }
}

// iOS 6 decides the child's reserved height ONCE, when the rotation layout runs.
// If we only hide the bar during that layout it still reserves the bar's ~49pt,
// so the rotated child is laid short and a black strip shows. Hiding the bar up
// front (here, before the rotation) makes UIKit compute the child at full height
// with the bar already gone — the same trick the working iPad path relies on.
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) return;
    if (LTPhoneDockKeepsTabBarVisible()) return; // keep the bar; don't fight the rotation
    NSInteger playerIndex = (NSInteger)(self.viewControllers.count - 1);
    if ((NSInteger)self.selectedIndex != playerIndex) return;
    BOOL toLandscape = (toInterfaceOrientation == UIInterfaceOrientationLandscapeLeft ||
                        toInterfaceOrientation == UIInterfaceOrientationLandscapeRight);
    if (toLandscape) {
        self.tabBarForcedHidden = YES;
        self.tabBar.hidden = YES;
    } else {
        self.tabBarForcedHidden = NO;
        [self showBar];
    }
}

// iOS 6 leaves the tab bar's UISnapshotView (a frozen copy of the bar used
// during rotation) stuck in the window as a sibling when we hide the bar
// mid-rotation. It never gets torn down, so a black 320x49 slab sits where the
// bar was. The snapshot only matters DURING the rotation animation; once the bar
// is hidden+collapsed we remove any window-level bar snapshot so the black slab
// can't render. (iOS 7+ tears it down on its own; the 5C never sees this.)
- (void)removeStaleTabBarSnapshot {
    UIWindow *win = self.view.window;
    if (!win) return;
    if (!self.tabBar.hidden || CGRectGetHeight(self.tabBar.frame) > 0.5f) return;
    for (UIView *sub in [win.subviews copy]) {
        if (sub == self.view || sub == self.tabBar) continue;
        if (![NSStringFromClass([sub class]) isEqualToString:@"UISnapshotView"]) continue;
        [sub removeFromSuperview];
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self updateForcedHiddenState];
    [self assertForcedHiddenTabBarLayout];
    [self removeStaleTabBarSnapshot];
    __unsafe_unretained LTTabBarController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf removeStaleTabBarSnapshot];
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateForcedHiddenState];
    [self assertForcedHiddenTabBarLayout];
    CGFloat bw = self.view.bounds.size.width;
    CGFloat bh = self.view.bounds.size.height;
    if (bw != self.lastDebugW || bh != self.lastDebugH || self.tabBarForcedHidden != self.lastDebugForced) {
        self.lastDebugW = bw;
        self.lastDebugH = bh;
        self.lastDebugForced = self.tabBarForcedHidden;
        LTLog(@"TABVC didLayout bounds=%.0fx%.0f bar=%@ barHidden=%d forced=%d idx=%ld dock=%d",
              bw, bh, NSStringFromCGRect(self.tabBar.frame), self.tabBar.hidden,
              self.tabBarForcedHidden, (long)self.selectedIndex, (int)(bw > bh));
        if (self.tabBarForcedHidden) {
            [self logDockHierarchy];
            __unsafe_unretained LTTabBarController *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [weakSelf logSettledDockState];
            });
        }
    }
}

// Diagnostic: comprehensive dump of the window AFTER the rotation animation has
// settled, so we can see exactly what occupies the lower screen in dock mode.
- (void)logSettledDockState {
    UIWindow *win = self.view.window;
    if (!win) return;
    UIView *selParent = nil;
    if (self.selectedViewController) selParent = self.selectedViewController.view.superview;
    LTLog(@"SETTLED win=%@ bar=%@ barHidden=%d forced=%d selParent=%@",
          NSStringFromCGRect(win.bounds), NSStringFromCGRect(self.tabBar.frame),
          self.tabBar.hidden, self.tabBarForcedHidden,
          selParent ? NSStringFromCGRect(selParent.frame) : @"(none)");
    [self logViews:win depth:0 prefix:@"WIN"];
}

- (void)logDockHierarchy {
    UIWindow *win = self.view.window;
    if (!win) return;
    [self logViews:win depth:0 prefix:@"WIN"];
}

- (void)logViews:(UIView *)v depth:(int)depth prefix:(NSString *)prefix {
    if (depth > 3) return;
    for (UIView *sub in v.subviews) {
        CGRect f = sub.frame;
        BOOL low = (CGRectGetMaxY(f) > 240.0f && f.size.height > 10.0f);
        if (low) {
            LTLog(@"DOCKHIER %@%@ frame=%@ hidden=%d alpha=%.2f bg=%@",
                  prefix, NSStringFromClass([sub class]), NSStringFromCGRect(f),
                  sub.hidden, sub.alpha, sub.backgroundColor);
        }
        [self logViews:sub depth:depth + 1 prefix:[prefix stringByAppendingString:@">"]];
    }
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    [self updateForcedHiddenState];
    [self assertForcedHiddenTabBarLayout];
    [self.view setNeedsLayout];
}

+ (UIImage *)snapshotContentOfView:(UIView *)view inRect:(CGRect)rect scale:(CGFloat)scale {
    if (rect.size.width < 1.0f || rect.size.height < 1.0f) return nil;
    CGSize px = CGSizeMake(ceilf(rect.size.width * scale), ceilf(rect.size.height * scale));
    if (px.width < 1.0f || px.height < 1.0f) return nil;
    // TEMP instrumentation: tab switching had a ~1s stall on the 3GS. Measuring
    // where it goes rather than guessing. Remove once the cause is fixed.
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    UIGraphicsBeginImageContext(px);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(ctx, scale, scale);
    if (rect.origin.x != 0.0f || rect.origin.y != 0.0f) {
        CGContextTranslateCTM(ctx, -rect.origin.x, -rect.origin.y);
    }
    // Prefer drawViewHierarchyInRect:afterScreenUpdates: where it exists (iOS 7+).
    // renderInContext: rasterises the whole hierarchy in software on the CPU,
    // which on a 3GS is a full-screen software render of every cell, image and
    // custom drawRect in the outgoing tab, done synchronously on the main thread
    // in the middle of the switch. That was the dominant cost of changing tabs.
    // The iOS 7 path is backed by the GPU and captures the already-composited
    // result, so it is far cheaper. iOS 6 has no such API and keeps the old
    // path -- which means the 3GS, the slowest device, is the one that cannot
    // avoid it.
    //
    // Both calls honour the context's CTM and take `rect` in the view's own
    // coordinates, so the scale/translate above applies identically either way.
    //
    // FALLBACK: drawViewHierarchyInRect:afterScreenUpdates: requires the view to
    // be in a visible window. If it returns nil (e.g. view is being torn down),
    // we fall back to renderInContext: which works on any layer.
    SEL hierarchySel = @selector(drawViewHierarchyInRect:afterScreenUpdates:);
    BOOL gpuBacked = [view respondsToSelector:hierarchySel];
    if (gpuBacked) {
        NSMethodSignature *sig = [view methodSignatureForSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)];
            [inv setTarget:view];
            CGRect r = rect;
            BOOL after = NO;
            [inv setArgument:&r atIndex:2];
            [inv setArgument:&after atIndex:3];
            [inv invoke];
        }
        // If the GPU path failed (returns nil), fall back to the CPU path.
        UIImage *gpuImage = UIGraphicsGetImageFromCurrentImageContext();
        if (gpuImage) {
            UIGraphicsEndImageContext();
            LTLog(@"TABPROF snapshot gpu=1 %.0fx%.0f took=%.0fms",
                  (double)px.width, (double)px.height,
                  (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);
            return gpuImage;
        }
        UIGraphicsEndImageContext();
        // Restart context for fallback
        UIGraphicsBeginImageContext(px);
        ctx = UIGraphicsGetCurrentContext();
        CGContextScaleCTM(ctx, scale, scale);
        if (rect.origin.x != 0.0f || rect.origin.y != 0.0f) {
            CGContextTranslateCTM(ctx, -rect.origin.x, -rect.origin.y);
        }
    }
    [view.layer renderInContext:ctx];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    LTLog(@"TABPROF snapshot gpu=0 %.0fx%.0f took=%.0fms",
          (double)px.width, (double)px.height,
          (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);
    return image;
}

- (CGRect)contentRectForTabBarController:(UITabBarController *)tabBarController {
    UIView *rootView = tabBarController.view;
    UINavigationController *nav = [tabBarController.selectedViewController isKindOfClass:[UINavigationController class]]
        ? (UINavigationController *)tabBarController.selectedViewController
        : nil;
    CGFloat width = rootView.bounds.size.width;
    CGFloat height = rootView.bounds.size.height;
    CGFloat contentTop = nav ? CGRectGetMaxY(nav.navigationBar.frame) : 0.0f;
    CGFloat tabHeight = [self effectiveTabBarHeightForBounds:rootView.bounds];
    return CGRectMake(0.0f, contentTop, width, height - contentTop - tabHeight);
}

// Height the tab bar actually occupies in the given bounds. Uses the frame
// position, not the `hidden` flag: on the iPad the split container docks the
// bar offscreen in landscape, and UITabBarController keeps even a hidden bar's
// frame in place, which would otherwise leave a dead strip under the player.
- (CGFloat)effectiveTabBarHeightForBounds:(CGRect)bounds {
    if (self.tabBar.hidden) return 0.0f;
    CGRect barFrame = self.tabBar.frame;
    if (barFrame.size.height < 1.0f) return 0.0f;
    if (CGRectGetMaxY(barFrame) > bounds.size.height + 0.5f) return 0.0f;
    if (CGRectGetMaxY(barFrame) < 0.5f) return 0.0f;
    return CGRectGetHeight(barFrame);
}

#pragma mark - UITabBarControllerDelegate

// Capture the outgoing CONTENT area only (bars are left alone). Snapshot is
// taken fresh at tap time so it's never outdated.
- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController {
    if (viewController == tabBarController.selectedViewController || self.fading) return NO;
    UIView *fromView = tabBarController.selectedViewController.view;
    if (!fromView || !fromView.window) return YES;

    self.slideFromIndex = (NSInteger)tabBarController.selectedIndex;
    self.slideToIndex = (NSInteger)[tabBarController.viewControllers indexOfObject:viewController];
    self.slideContentRect = [self contentRectForTabBarController:tabBarController];
    // The modern themes' crossfade needs the outgoing screen captured while it
    // is still on screen. By the time the selection changes, the tab controller
    // has already taken the view out of the hierarchy, so there is nothing
    // left to capture.
    self.outgoingOverlay = [self snapshotOverlayForView:fromView];
    return YES;
}

// A still of the outgoing screen, used as the first half of the modern
// themes' crossfade.
//
// The view itself cannot be reused: it belongs to the tab controller, which
// takes it out of the hierarchy when the selection changes. A snapshot is a
// plain image and can be faded over the new screen freely.
- (UIImageView *)snapshotOverlayForView:(UIView *)view {
    if (!view || !view.window) return nil;
    if (view.bounds.size.width <= 0.0f || view.bounds.size.height <= 0.0f) return nil;

    UIGraphicsBeginImageContextWithOptions(view.bounds.size, YES, 0.0f);
    if ([view respondsToSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)]) {
        NSMethodSignature *sig = [view methodSignatureForSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setSelector:@selector(drawViewHierarchyInRect:afterScreenUpdates:)];
        [inv setTarget:view];
        CGRect rect = view.bounds;
        BOOL after = NO;
        [inv setArgument:&rect atIndex:2];
        [inv setArgument:&after atIndex:3];
        [inv invoke];
    } else {
        // iOS 6 and earlier: the layer can still be rendered into the context.
        [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!image) return nil;

    UIImageView *overlay = [[UIImageView alloc] initWithImage:image];
    overlay.frame = view.frame;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.userInteractionEnabled = NO;
    return overlay;
}

// The modern themes crossfade between tabs: the outgoing screen fades out
// while the incoming one fades in, over a fifth of a second. The native theme
// keeps the instant switch it has always had.
- (void)crossfadeWithOverlay:(UIImageView *)overlay to:(UIView *)incoming {
    if (!incoming) return;
    if (!overlay) {
        incoming.alpha = 1.0f;
        return;
    }
    // Above the content, below the tab bar.
    [self.view insertSubview:overlay belowSubview:self.tabBar];
    incoming.alpha = 0.0f;
    // The crossfade follows the transition speed setting, like every other
    // transition in the app. The base is a tenth of a second; the setting
    // scales it, so the fastest it goes is a twentieth.
    CGFloat duration = 0.1f;
    [LTTransitionSettings animateWithDuration:duration
                          delay:0.0f
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        incoming.alpha = 1.0f;
        overlay.alpha = 0.0f;
    } completion:^(BOOL finished) {
        incoming.alpha = 1.0f;
        [overlay removeFromSuperview];
    }];
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    // TEMP instrumentation: see -snapshotContentOfView. Remove once fixed.
    CFAbsoluteTime tEnter = CFAbsoluteTimeGetCurrent();
    NSInteger fromIndex = self.slideFromIndex;
    NSInteger toIndex = (NSInteger)[tabBarController.viewControllers indexOfObject:viewController];
    if (fromIndex == toIndex) return;
    [self announceSelectionTo:toIndex];
    BOOL forcingPortrait = [self shouldForcePortraitForIndex:toIndex];
    [self enforcePortraitAwayFromPlayerForIndex:toIndex];
    // Forcing portrait re-frames everything; the slide transition would re-apply
    // stale landscape bounds on top, so let the rotation be the transition.
    if (forcingPortrait) return;

    // Animations disabled → instant switch.
    if (![LTTransitionSettings animationsEnabled]) {
        LTLog(@"TABPROF switch %ld->%ld total=%.0fms (animations off)", (long)fromIndex, (long)toIndex,
              (CFAbsoluteTimeGetCurrent() - tEnter) * 1000.0);
        return;
    }

    // The modern themes crossfade; the native theme switches instantly.
    if ([LTTheme isModern]) {
        UIImageView *overlay = self.outgoingOverlay;
        self.outgoingOverlay = nil;
        [self crossfadeWithOverlay:overlay to:viewController.view];
    }
    LTLog(@"TABPROF switch %ld->%ld total=%.0fms", (long)fromIndex, (long)toIndex,
          (CFAbsoluteTimeGetCurrent() - tEnter) * 1000.0);
}

#pragma mark - Navigation

- (void)showNowPlaying {
    NSInteger index = (NSInteger)self.viewControllers.count - 1;
    if (self.selectedIndex != index) {
        self.selectedIndex = index;
    }
}

// Announce the new selection exactly once no matter how it changed. Programmatic
// selection (sidebar taps, showNowPlaying) does not reliably reach the tab-bar
// delegate, so the setter announces too, and the last-seen index dedupes it
// against the delegate path to avoid double-firing.
- (void)announceSelectionTo:(NSInteger)index {
    if (index == self.lastAnnouncedIndex) return;
    self.lastAnnouncedIndex = index;
    if (self.selectionDidChange) self.selectionDidChange(index);
}

// Leaving the Now Playing tab while the landscape dock is up must snap back to
// portrait: only the player tab permits landscape (see supportedInterfaceOrientations).
// iOS 6 does not re-check the orientation mask just because it narrowed on a tab
// switch, and the device is physically sideways, so the app would stay landscape.
// Re-installing the window's root view controller makes UIKit re-read the (now
// portrait-only) mask and rotate down. The SAME tab controller instance is put
// back, so the current tab and all state are preserved. On iPad the tab controller
// is nested in the split container (not the root), so we leave it alone there.
// True when a selection change means we are leaving the player tab while the
// landscape dock is up, so the app is about to be forced back to portrait.
- (BOOL)shouldForcePortraitForIndex:(NSInteger)index {
    NSInteger playerIndex = (NSInteger)(self.viewControllers.count - 1);
    if (index == playerIndex) return NO;               // still on the player tab
    CGRect b = self.view.bounds;
    if (b.size.width <= b.size.height) return NO;      // already portrait
    UIWindow *win = self.view.window;
    return (win && win.rootViewController == self);   // iPhone; iPad nested
}

- (void)enforcePortraitAwayFromPlayerForIndex:(NSInteger)index {
    NSInteger playerIndex = (NSInteger)(self.viewControllers.count - 1);
    if (index == playerIndex) return;                  // still on the player tab
    CGRect b = self.view.bounds;
    if (b.size.width <= b.size.height) return;        // already portrait
    UIWindow *win = self.view.window;
    if (!win || win.rootViewController != self) return; // iPad split container
    win.rootViewController = [[UIViewController alloc] init];
    win.rootViewController = self;
    // The tab we landed on may still be sized for the old landscape bounds, so it
    // renders sideways inside a now-portrait window ("landscape in a portrait
    // frame"). Snap it to the portrait tab bounds and relayout.
    UIViewController *sel = self.selectedViewController;
    if (sel.isViewLoaded) {
        CGRect b = self.view.bounds;
        CGFloat barH = [self effectiveTabBarHeightForBounds:b];
        sel.view.frame = CGRectMake(0.0f, 0.0f, b.size.width, b.size.height - barH);
        [sel.view setNeedsLayout];
        [sel.view layoutIfNeeded];
    }
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];
    [self announceSelectionTo:(NSInteger)selectedIndex];
    [self enforcePortraitAwayFromPlayerForIndex:(NSInteger)selectedIndex];
}

@end
