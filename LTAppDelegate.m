#import "LTAppDelegate.h"
#import <objc/message.h>
#import "LTSearchViewController.h"
#import "LTLibraryViewController.h"
#import "LTHomeViewController.h"
#import "LTSettingsViewController.h"
#import "LTPlayerViewController.h"
#import "LTPlayerController.h"
#import "LTListenBrainzScrobbler.h"
#import "LTPlaylistStore.h"
#import "LTTabBarController.h"
#import "LTSplitContainerViewController.h"
#import "LTGraphics.h"
#import "LTDebugSettings.h"
#import "LTiPodViewController.h"
#import "LTWebShellViewController.h"
#import "LTOneHandedMode.h"
#import "LTAppIcon.h"
#import "LTLog.h"
// For LTTempDirectory(), used by the crash handler below. LTLog.h no longer
// re-exports this: it was only ever reaching here by accident.
#import "LTFilePaths.h"
// For LTTheme refreshAppearance, which invalidates the cached appearance probe.
#import "LTTheme.h"
#import "LTCardNavBar.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "LTTransitionSettings.h"

@interface LTAppDelegate ()
@property (nonatomic, assign) BOOL remoteCommandsEnabled;
@property (nonatomic, strong) NSTimer *mainThreadHeartbeat;
@property (nonatomic, assign) CFAbsoluteTime lastHeartbeat;
- (void)lt_makeRemoteResponderFirst;
@end

@implementation LTAppDelegate

static void LTUncaughtExceptionHandler(NSException *e) {
    NSString *path = [LTTempDirectory() stringByAppendingPathComponent:@"lt_crash.txt"];
    NSString *text = [NSString stringWithFormat:@"REASON: %@\nNAME: %@\nCALLSTACK:\n%@\n",
                      e.reason, e.name, [e callStackSymbols]];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    LTLog(@"UNCAUGHT EXCEPTION %@ %@\n%@", e.name, e.reason, e.callStackSymbols);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    { NSString *p=@"/var/mobile/Documents/LegacyMusic/lm_debug.log"; NSFileHandle *f=[NSFileHandle fileHandleForWritingAtPath:p]; if(!f){[@"" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; f=[NSFileHandle fileHandleForWritingAtPath:p];} if(f){[f seekToEndOfFile]; [f writeData:[@"APP didFinishLaunching enter\n" dataUsingEncoding:NSUTF8StringEncoding]]; [f closeFile];} }
    NSSetUncaughtExceptionHandler(&LTUncaughtExceptionHandler);
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [session setActive:YES error:NULL];
    LTLog(@"APP didFinishLaunching");
    // Start the loopback SOCKS relay if the user enabled it. It is harmless when
    // off and idle (one listening socket on 127.0.0.1) when on.
    // LTTheme caches its appearance probe (see LTTheme). One observer here covers
    // every view controller, rather than each of them having to invalidate. By
    // string so this compiles against the old SDKs the app builds with.
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UITraitCollectionDidChangeNotification"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        [LTTheme refreshAppearance];
    }];
    // TEMP instrumentation: a main-thread heartbeat. The point is to catch the
    // gap between "user taps a tab" and "-didSelectViewController: is entered" —
    // if the main thread is busy, the touch event just waits in the queue and
    // none of the timing probes inside the tab controller can see it.
    self.mainThreadHeartbeat = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                              target:self
                                                            selector:@selector(mainThreadHeartbeatTick:)
                                                            userInfo:nil
                                                             repeats:YES];
    self.lastHeartbeat = CFAbsoluteTimeGetCurrent();
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self setupRemoteCommandCenter];
    [self becomeFirstResponder];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // The status bar area is painted by the window, so a window that is not the
    // theme's background shows as a black band at the top of the screen.
    self.window.backgroundColor = [LTTheme background];

    if ([LTiPodViewController isEnabled]) {
        self.window.rootViewController = [[LTiPodViewController alloc] init];
    } else {
        self.window.rootViewController = [LTAppDelegate rootViewControllerForTheme];
    }
    // The root view fills the window, so it - not the window - is what shows
    // behind the status bar. Without this the bar sits on a black band.
    self.window.rootViewController.view.backgroundColor = [LTTheme background];
    
    // Set status bar style based on theme. Avoid private status bar view hacks on
    // modern iOS (fragile and unnecessary), but keep legacy behavior where needed.
    [[UIApplication sharedApplication] setStatusBarStyle:[LTTheme statusBarStyle]];
    if ([[[UIDevice currentDevice] systemVersion] floatValue] < 7.0f) {
        @try {
            UIView *statusBar = [[[UIApplication sharedApplication] valueForKey:@"statusBarWindow"] valueForKey:@"statusBar"];
            if ([statusBar respondsToSelector:@selector(setBackgroundColor:)]) {
                statusBar.backgroundColor = [LTTheme statusBarBackgroundColor];
            }
        } @catch (NSException *e) {
            LTLog(@"STATUSBAR legacy style failed: %@", e);
        }
    }
    
    [self.window makeKeyAndVisible];
    [self lt_makeRemoteResponderFirst];
    [LTAppDelegate applyDisplayModeAnimated:NO];
    [LTAppDelegate installQuickActions];
    [LTListenBrainzScrobbler sharedScrobbler];
    [[LTListenBrainzScrobbler sharedScrobbler] flushPendingScrobbles];
    [self logRootHierarchy];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:LTThemeDidChangeNotification
                                               object:nil];
    return YES;
}

// The root for the selected theme.
//
// Native is the app as it has always been. The modern pair are served by a web
// view running the desktop app's UI, which is why the modern themes are gated
// to devices that can run one.
//
// iPod mode is not a theme and is handled by the caller, not here: it has its
// own chrome and deliberately does not follow the theme.
+ (UIViewController *)rootViewControllerForTheme {
    // The modern themes are the native app, restyled. They used to be the
    // desktop app's web UI served in a web view, which was abandoned: iOS 9's
    // WebKit has no CSS custom properties, no modules, no fetch and no flexbox
    // gap, and every one of those had to be worked around. The native screens
    // already exist and already work, so they are simply painted with the
    // desktop app's Material 3 palette instead.
    return [LTAppDelegate standardRootViewController];
}

// Rebuilds the UI so every screen picks up the new theme at once.
//
// Recolouring in place would mean finding every view that cached a colour, and
// missing one shows up as a stray blue label. Rebuilding the root is heavier
// but it cannot be half-applied, and a theme change is a deliberate action where
// losing the current navigation stack is an acceptable cost.
//
// iPod mode is left alone: it has its own chrome and deliberately does not
// follow the theme.
- (void)themeDidChange:(NSNotification *)notification {
    if ([LTiPodViewController isEnabled]) return;
    UIViewController *root = [LTAppDelegate rootViewControllerForTheme];
    self.window.rootViewController = root;
    // The root view fills the window, so it - not the window - is what shows
    // behind the status bar. Without this the bar sits on a black band.
    root.view.backgroundColor = [LTTheme background];
    
    // Update status bar for new theme
    {
        UIView *statusBar = [[[UIApplication sharedApplication] valueForKey:@"statusBarWindow"] valueForKey:@"statusBar"];
        if ([statusBar respondsToSelector:@selector(setBackgroundColor:)]) {
            statusBar.backgroundColor = [LTTheme statusBarBackgroundColor];
        }
        [[UIApplication sharedApplication] setStatusBarStyle:[LTTheme statusBarStyle]];
    }
    
    [self.window makeKeyAndVisible];
    [self lt_makeRemoteResponderFirst];
    [LTAppDelegate applyDisplayModeAnimated:NO];
}

// The standard tab-bar root, wrapped in the iPad split container when running
// on iPad. Kept in sync with LTiPodViewController.makeStandardRoot.
+ (UIViewController *)standardRootViewController {
    LTTabBarController *tabBar = [LTAppDelegate makeTabBarController];
    if ([LTSplitContainerViewController isSupported]) {
        return [[LTSplitContainerViewController alloc] initWithTabController:tabBar];
    }
    return tabBar;
}

// Builds a navigation controller for one of the tabs.
//
// The modern theme needs its own navigation bar, and the only way to give a
// navigation controller a different bar class is to say so when it is created -
// swapping the bar afterwards is too late, because the controller has already
// laid out around the one it made. initWithNavigationBarClass: is iOS 5, so
// this needs no availability guard.
// Logs what is actually in the window, so a blank screen can be diagnosed
// rather than guessed at. A nil child or a zero-sized view looks identical to
// the user and very different in a log.
- (void)logRootHierarchy {
    UIViewController *root = self.window.rootViewController;
    LTLog(@"ROOT %@ view=%@ bounds=%@",
          NSStringFromClass([root class]),
          root.view ? NSStringFromCGRect(root.view.frame) : @"nil",
          root.view ? NSStringFromCGRect(root.view.bounds) : @"nil");
    if (![root isKindOfClass:[UITabBarController class]]) return;
    UITabBarController *tabs = (UITabBarController *)root;
    LTLog(@"ROOT tabs=%d selected=%d barItems=%d barFrame=%@",
          (int)tabs.viewControllers.count, (int)tabs.selectedIndex,
          (int)tabs.tabBar.items.count, NSStringFromCGRect(tabs.tabBar.frame));
    // What is actually in the window, and what colour is behind the status bar.
    for (UIView *sub in self.window.subviews) {
        LTLog(@"ROOT  window subview=%@ frame=%@ bg=%@",
              NSStringFromClass([sub class]), NSStringFromCGRect(sub.frame),
              sub.backgroundColor ? [sub.backgroundColor description] : @"nil");
    }
    LTLog(@"ROOT window bg=%@ rootView bg=%@ statusBar=%@",
          [self.window.backgroundColor description],
          [root.view.backgroundColor description],
          [[UIApplication sharedApplication] statusBarFrame]);
    for (UIViewController *child in tabs.viewControllers) {
        LTLog(@"ROOT  child=%@ view=%@", NSStringFromClass([child class]),
              child.view ? NSStringFromCGRect(child.view.frame) : @"nil");
        if (![child isKindOfClass:[UINavigationController class]]) continue;
        UINavigationController *nav = (UINavigationController *)child;
        UIViewController *top = nav.topViewController;
        LTLog(@"ROOT   bar=%@ top=%@ topView=%@",
              NSStringFromClass([nav.navigationBar class]),
              NSStringFromClass([top class]),
              top.view ? NSStringFromCGRect(top.view.frame) : @"nil");
    }
}

+ (UINavigationController *)navControllerForRoot:(UIViewController *)root {
    if (![LTTheme isModern]) {
        return [[UINavigationController alloc] initWithRootViewController:root];
    }
    // Custom navigation bar class is fragile across iOS versions (and can crash
    // on newer UIKit, e.g. iOS 9). Prefer standard nav controller there and
    // paint its bar in place instead - swapping the bar class after creation
    // does not replace the bar that is already in the hierarchy.
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 9.0f) {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
        [LTCardNavBar applyModernStyleToNavigationBar:nav.navigationBar];
        return nav;
    }
    UINavigationController *nav =
        [[UINavigationController alloc] initWithNavigationBarClass:[LTCardNavBar class]
                                                    toolbarClass:[UIToolbar class]];
    // If the class-based initialiser did not produce a controller, fall back
    // rather than handing the tab controller a nil child - which would leave the
    // tab bar with no items and the screen with no content.
    if (!nav) {
        LTLog(@"WEB nav fallback: class-based init returned nil");
        nav = [[UINavigationController alloc] initWithRootViewController:root];
    } else {
        // initWithNavigationBarClass:toolbarClass: gives the controller its bar
        // class but leaves it with NO root view controller - unlike
        // initWithRootViewController:. Without this the navigation controller is
        // empty, so the tab bar has items but every screen behind them is blank.
        [nav setViewControllers:@[root] animated:NO];
    }
    return nav;
}

+ (LTTabBarController *)makeTabBarController {
    NSMutableArray *controllers = [NSMutableArray array];

    LTHomeViewController *home = [[LTHomeViewController alloc] init];
    home.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Home" image:[LTGraphics homeIcon] tag:0];
    UINavigationController *homeNav = [LTAppDelegate navControllerForRoot:home];
    [controllers addObject:homeNav];

    LTSearchViewController *search = [[LTSearchViewController alloc] initWithType:@"songs"];
    search.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Search" image:[LTGraphics searchIcon] tag:0];
    UINavigationController *searchNav = [LTAppDelegate navControllerForRoot:search];
    [controllers addObject:searchNav];

    LTLibraryViewController *library = [[LTLibraryViewController alloc] init];
    library.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Library" image:[LTGraphics libraryIcon] tag:0];
    UINavigationController *libraryNav = [LTAppDelegate navControllerForRoot:library];
    [controllers addObject:libraryNav];

    LTSettingsViewController *settings = [[LTSettingsViewController alloc] init];
    settings.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:[LTGraphics settingsIcon] tag:0];
    UINavigationController *settingsNav = [LTAppDelegate navControllerForRoot:settings];
    [controllers addObject:settingsNav];

    LTPlayerViewController *nowPlaying = [[LTPlayerViewController alloc] init];
    nowPlaying.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Now Playing"
                                                          image:[LTGraphics playIcon]
                                                            tag:0];
    UINavigationController *nowPlayingNav = [LTAppDelegate navControllerForRoot:nowPlaying];
    [controllers addObject:nowPlayingNav];

    LTTabBarController *tabBar = [[LTTabBarController alloc] init];
    tabBar.viewControllers = controllers;
    return tabBar;
}

+ (void)applyDisplayModeAnimated:(BOOL)animated {
    UIWindow *window = [(LTAppDelegate *)[[UIApplication sharedApplication] delegate] window];
    if (!window) return;
    UIView *root = window.rootViewController.view;
    if (!root) return;

    if (animated) {
        [LTTransitionSettings animateWithDuration:0.35f animations:^{
            [LTAppDelegate applyDisplayModeOnce:window root:root];
        }];
    } else {
        [LTAppDelegate applyDisplayModeOnce:window root:root];
    }
}

+ (void)applyDisplayModeOnce:(UIWindow *)window root:(UIView *)root {
    CGRect screen = window.bounds;
    // One-handed mode takes priority: it draws the classic 320x480 layout, but
    // pinned to a bottom corner instead of centered.
    BOOL oneHanded = [LTOneHandedMode isActive];
    BOOL forceNonWide = [LTDebugSettings forceNonWidescreen];
    BOOL forceWide = [LTDebugSettings forceWidescreen];

    CGFloat virtualW = screen.size.width;
    CGFloat virtualH = screen.size.height;
    if (oneHanded) {
        CGSize handSize = [LTOneHandedMode virtualSize];
        virtualW = handSize.width;
        virtualH = handSize.height;
    } else if (forceNonWide) {
        virtualW = 320.0f;
        virtualH = 480.0f;
    } else if (forceWide) {
        virtualW = 320.0f;
        virtualH = 568.0f;
    }

    BOOL forced = (virtualW != screen.size.width || virtualH != screen.size.height);

    root.transform = CGAffineTransformMake(1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f);
    if (forced) {
        if (oneHanded) {
            root.frame = [LTOneHandedMode frameInBounds:screen];
        } else {
            root.frame = CGRectMake(round((screen.size.width - virtualW) / 2.0f),
                                    round((screen.size.height - virtualH) / 2.0f),
                                    virtualW, virtualH);
        }
        CGFloat scale = MIN(screen.size.width / virtualW, screen.size.height / virtualH);
        if (scale < 1.0f) {
            root.transform = CGAffineTransformMakeScale(scale, scale);
        }
        window.backgroundColor = [UIColor blackColor];
        root.autoresizingMask = UIViewAutoresizingNone;
    } else {
        root.frame = window.bounds;
        // The window's colour shows in the status bar area, so it has to be the
        // theme's background rather than nothing, which is black.
        window.backgroundColor = [LTTheme background];
        root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
}

- (void)mainThreadHeartbeatTick:(NSTimer *)timer {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    double gap = now - self.lastHeartbeat;
    self.lastHeartbeat = now;
    if (gap > 0.15) LTLog(@"TABPROF MAINBLOCK %.0fms", gap * 1000.0);
}

- (void)applicationWillResignActive:(UIApplication *)application {
    LTLog(@"APP willResignActive");
    // Stats writes are debounced; make sure nothing pending is lost when the app
    // leaves the foreground (backgrounded, or killed while backgrounded).
    [[LTPlaylistStore sharedStore] flushListeningStats];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    // Locking the phone is the moment the lock-screen buttons need a responder.
    [self lt_makeRemoteResponderFirst];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    LTLog(@"APP didEnterBackground");
    [[LTPlaylistStore sharedStore] flushListeningStats];
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:YES error:NULL];
    [self lt_makeRemoteResponderFirst];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    LTLog(@"APP didBecomeActive");
    // Here rather than in didFinishLaunching: setAlternateIconName: is unreliable
    // before the app is frontmost. The defaults flag keeps it to one attempt.
    [LTAppIcon applyModernIconIfNeeded];
    [self lt_makeRemoteResponderFirst];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

// The app delegate is not guaranteed to be in the remote-control responder
// chain, especially on iOS 4. Walk down from the window root to the first
// controller that explicitly opts in; LTTabBarController does, and handles the
// event by forwarding it to the shared player. Fall back to the delegate so
// older/custom roots still have a chance.
- (void)lt_makeRemoteResponderFirst {
    UIResponder *responder = (UIResponder *)self.window.rootViewController;
    while (responder) {
        if ([responder canBecomeFirstResponder] && [responder becomeFirstResponder]) {
            LTLog(@"REMOTE first responder=%@", NSStringFromClass([responder class]));
            return;
        }
        if ([responder isKindOfClass:[UITabBarController class]]) {
            responder = (UIResponder *)((UITabBarController *)responder).selectedViewController;
        } else if ([responder isKindOfClass:[UINavigationController class]]) {
            responder = (UIResponder *)((UINavigationController *)responder).topViewController;
        } else {
            responder = nil;
        }
    }
    if ([self becomeFirstResponder]) {
        LTLog(@"REMOTE first responder=LTAppDelegate");
    }
}

- (void)setupRemoteCommandCenter {
    Class cls = NSClassFromString(@"MPRemoteCommandCenter");
    if (!cls) return;
    id center = [cls performSelector:@selector(sharedCommandCenter)];
    if (!center) return;
    self.remoteCommandsEnabled = YES;

    id cmd;
    cmd = [center performSelector:@selector(playCommand)]; if (cmd) ((void(*)(id,SEL,id,SEL))objc_msgSend)(cmd, @selector(addTarget:action:), self, @selector(remotePlayCommand:));
    cmd = [center performSelector:@selector(pauseCommand)]; if (cmd) ((void(*)(id,SEL,id,SEL))objc_msgSend)(cmd, @selector(addTarget:action:), self, @selector(remotePauseCommand:));
    cmd = [center performSelector:@selector(togglePlayPauseCommand)]; if (cmd) ((void(*)(id,SEL,id,SEL))objc_msgSend)(cmd, @selector(addTarget:action:), self, @selector(remoteTogglePlayPauseCommand:));
    cmd = [center performSelector:@selector(nextTrackCommand)]; if (cmd) ((void(*)(id,SEL,id,SEL))objc_msgSend)(cmd, @selector(addTarget:action:), self, @selector(remoteNextCommand:));
    cmd = [center performSelector:@selector(previousTrackCommand)]; if (cmd) ((void(*)(id,SEL,id,SEL))objc_msgSend)(cmd, @selector(addTarget:action:), self, @selector(remotePreviousCommand:));

    cmd = [center performSelector:@selector(skipForwardCommand)];
    if (cmd && [cmd respondsToSelector:@selector(setEnabled:)]) [(id)cmd setEnabled:NO];
    cmd = [center performSelector:@selector(skipBackwardCommand)];
    if (cmd && [cmd respondsToSelector:@selector(setEnabled:)]) [(id)cmd setEnabled:NO];
    if ([center respondsToSelector:@selector(changePlaybackPositionCommand)]) {
        cmd = [center performSelector:@selector(changePlaybackPositionCommand)];
        if (cmd) ((void(*)(id,SEL,id,SEL))objc_msgSend)(cmd, @selector(addTarget:action:), self, @selector(remoteChangePlaybackPositionCommand:));
    }
}

- (NSInteger)remotePlayCommand:(id)event {
    [[LTPlayerController sharedController] playMovie];
    return 0;
}

- (NSInteger)remotePauseCommand:(id)event {
    [[LTPlayerController sharedController] pausePlayback];
    return 0;
}

- (NSInteger)remoteTogglePlayPauseCommand:(id)event {
    [[LTPlayerController sharedController] togglePlayPause];
    return 0;
}

- (NSInteger)remoteNextCommand:(id)event {
    [[LTPlayerController sharedController] nextTrack];
    return 0;
}

- (NSInteger)remotePreviousCommand:(id)event {
    [[LTPlayerController sharedController] previousTrack];
    return 0;
}



- (NSInteger)remoteChangePlaybackPositionCommand:(id)event {
    NSTimeInterval t = 0;
    if ([event respondsToSelector:@selector(positionTime)]) {
        t = [[event performSelector:@selector(positionTime)] doubleValue];
    }
    [[LTPlayerController sharedController] seekToTime:t];
    return 0;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (self.remoteCommandsEnabled) return;
    [[LTPlayerController sharedController] handleRemoteControlEvent:event];
}
#pragma mark - Home screen quick actions

// Quick actions are a home screen feature of iOS 9+. Resolve classes at runtime
// so older iOS (4.x/5.x/6.x) does not require weak/strong-linked 3D Touch symbols.
+ (void)installQuickActions {
    UIApplication *app = [UIApplication sharedApplication];
    if (![app respondsToSelector:@selector(setShortcutItems:)]) {
        LTLog(@"QA unavailable on this OS");
        return;
    }

    Class iconClass = NSClassFromString(@"UIApplicationShortcutIcon");
    Class itemClass = NSClassFromString(@"UIApplicationShortcutItem");
    if (!iconClass || !itemClass) return;

    // Icon type values (UIApplicationShortcutIconType): Search=3, Compose=0, Play=1, Shuffle=6.
    // Use numeric values to avoid compile-time SDK constants/symbol coupling.
    NSMutableArray *items = [NSMutableArray array];
    NSArray *specs = @[@[@"search",     @"Search",      @3],
                       @[@"library",    @"Library",     @0],
                       @[@"nowplaying", @"Now Playing", @1],
                       @[@"shuffleall", @"Shuffle All", @6]];
    for (NSArray *spec in specs) {
        NSInteger iconType = [[spec objectAtIndex:2] integerValue];
        id icon = nil;
        SEL iconSel = NSSelectorFromString(@"iconWithType:");
        if ([iconClass respondsToSelector:iconSel]) {
            icon = ((id (*)(id, SEL, NSInteger))objc_msgSend)(iconClass, iconSel, iconType);
        }
        if (!icon) continue;

        id item = [itemClass alloc];
        SEL initSel = NSSelectorFromString(@"initWithType:localizedTitle:localizedSubtitle:icon:userInfo:");
        if (![item respondsToSelector:initSel]) continue;
        item = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(item, initSel,
                                                                    [spec objectAtIndex:0],
                                                                    [spec objectAtIndex:1],
                                                                    nil, icon, nil);
        if (item) [items addObject:item];
    }

    SEL setSel = @selector(setShortcutItems:);
    if ([app respondsToSelector:setSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(app, setSel, items);
    }
    LTLog(@"QA installed %lu item(s)", (unsigned long)items.count);
}

// UIKit only sends this on iOS 9+.
- (void)application:(UIApplication *)application
    performActionForShortcutItem:(id)shortcutItem
                 completionHandler:(void (^)(BOOL success))completionHandler {
    NSString *type = nil;
    if ([shortcutItem respondsToSelector:@selector(type)]) {
        type = [shortcutItem performSelector:@selector(type)];
    }
    [LTAppDelegate handleQuickActionType:type];
    if (completionHandler) completionHandler(YES);
}

+ (void)handleQuickActionType:(NSString *)type {
    LTTabBarController *tabs = [LTAppDelegate activeTabBarController];

    // Starts playing, so it works even in iPod mode where there are no tabs.
    if ([type isEqualToString:@"shuffleall"]) {
        NSArray *songs = [[LTPlaylistStore sharedStore] libraryTracks];
        if (!songs.count) return;
        LTPlayerController *player = [LTPlayerController sharedController];
        player.repeatMode = LTRepeatModeAll;
        player.queueSourceName = @"Library";
        [player playQueue:songs shuffle:YES];
        if (tabs) [tabs showNowPlaying];
        return;
    }

    if (!tabs) return;

    if ([type isEqualToString:@"search"]) {
        [tabs setSelectedIndex:1];
        UIViewController *root = [LTAppDelegate rootOfTab:1 inTabs:tabs];
        if ([root isKindOfClass:[LTSearchViewController class]]) {
            [(LTSearchViewController *)root focusSearchField];
        }
    } else if ([type isEqualToString:@"library"]) {
        [tabs setSelectedIndex:2];
        UIViewController *root = [LTAppDelegate rootOfTab:2 inTabs:tabs];
        if ([root isKindOfClass:[LTLibraryViewController class]]) {
            [(LTLibraryViewController *)root showSongsSegment];
        }
    } else if ([type isEqualToString:@"nowplaying"]) {
        [tabs showNowPlaying];
    }
}

// The root controller of the navigation stack sitting at the given tab index.
+ (UIViewController *)rootOfTab:(NSInteger)index inTabs:(LTTabBarController *)tabs {
    if (index < 0 || index >= (NSInteger)tabs.viewControllers.count) return nil;
    UIViewController *controller = [tabs.viewControllers objectAtIndex:(NSUInteger)index];
    if (![controller isKindOfClass:[UINavigationController class]]) return nil;
    NSArray *vcs = [(UINavigationController *)controller viewControllers];
    return [vcs count] ? [vcs objectAtIndex:0] : nil;
}

// The root is the tab bar controller normally, the split container on iPad, and
// the iPod controller when that mode is on.
+ (LTTabBarController *)activeTabBarController {
    UIViewController *root = ((LTAppDelegate *)[[UIApplication sharedApplication] delegate]).window.rootViewController;
    if ([root isKindOfClass:[LTSplitContainerViewController class]]) {
        return [(LTSplitContainerViewController *)root tabController];
    }
    if ([root isKindOfClass:[LTTabBarController class]]) {
        return (LTTabBarController *)root;
    }
    return nil;
}



- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    if (![[url scheme] isEqualToString:@"legacymusic"]) return NO;
    // listenbrainz?token=...
    NSString *token = nil;
    NSString *q = [url query];
    for (NSString *pair in [q componentsSeparatedByString:@"&"]) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2 && [[kv objectAtIndex:0] isEqualToString:@"token"]) {
            token = [kv objectAtIndex:1];
            break;
        }
    }
    if (token.length) {
        [[LTListenBrainzScrobbler sharedScrobbler] fetchSessionForToken:token completion:^(BOOL ok, NSError *err) {
            NSString *title = ok ? @"Connected" : @"ListenBrainz";
            NSString *msg = ok ? @"Scrobbling to ListenBrainz is enabled." : (err.localizedDescription ?: @"Could not connect");
            UIAlertView *a = [[UIAlertView alloc] initWithTitle:title
                                                        message:msg
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
            [a show];
        }];
        return YES;
    }
    return NO;
}
@end
