#import "LTAppDelegate.h"
#import "LTSearchViewController.h"
#import "LTLibraryViewController.h"
#import "LTHomeViewController.h"
#import "LTSettingsViewController.h"
#import "LTPlayerViewController.h"
#import "LTPlayerController.h"
#import "LTTabBarController.h"
#import "LTGraphics.h"
#import "LTLog.h"
#import <AVFoundation/AVFoundation.h>

@implementation LTAppDelegate

static void LTUncaughtExceptionHandler(NSException *e) {
    NSString *path = @"/tmp/lt_crash.txt";
    NSString *text = [NSString stringWithFormat:@"REASON: %@\nNAME: %@\nCALLSTACK:\n%@\n",
                      e.reason, e.name, [e callStackSymbols]];
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    LTLog(@"UNCAUGHT EXCEPTION %@ %@\n%@", e.name, e.reason, e.callStackSymbols);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSSetUncaughtExceptionHandler(&LTUncaughtExceptionHandler);
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [session setActive:YES error:NULL];
    LTLog(@"APP didFinishLaunching");
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    NSMutableArray *controllers = [NSMutableArray array];

    LTHomeViewController *home = [[LTHomeViewController alloc] init];
    home.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Home" image:[LTGraphics homeIcon] tag:0];
    UINavigationController *homeNav = [[UINavigationController alloc] initWithRootViewController:home];
    [controllers addObject:homeNav];

    LTSearchViewController *search = [[LTSearchViewController alloc] initWithType:@"songs"];
    search.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Search" image:[LTGraphics searchIcon] tag:0];
    UINavigationController *searchNav = [[UINavigationController alloc] initWithRootViewController:search];
    [controllers addObject:searchNav];

    LTLibraryViewController *library = [[LTLibraryViewController alloc] init];
    library.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Library" image:[LTGraphics libraryIcon] tag:0];
    UINavigationController *libraryNav = [[UINavigationController alloc] initWithRootViewController:library];
    [controllers addObject:libraryNav];

    LTSettingsViewController *settings = [[LTSettingsViewController alloc] init];
    settings.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Settings" image:[LTGraphics settingsIcon] tag:0];
    UINavigationController *settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];
    [controllers addObject:settingsNav];

    LTPlayerViewController *nowPlaying = [[LTPlayerViewController alloc] init];
    nowPlaying.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Now Playing" image:[UIImage imageNamed:@"IcoPlay"] tag:0];
    UINavigationController *nowPlayingNav = [[UINavigationController alloc] initWithRootViewController:nowPlaying];
    [controllers addObject:nowPlayingNav];

    UITabBarController *tabBar = [[LTTabBarController alloc] init];
    tabBar.viewControllers = controllers;
    self.window.rootViewController = tabBar;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    LTLog(@"APP willResignActive");
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    LTLog(@"APP didEnterBackground");
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:YES error:NULL];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    LTLog(@"APP didBecomeActive");
    [self becomeFirstResponder];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    LTPlayerController *controller = [LTPlayerController sharedController];
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlPlay:
        case UIEventSubtypeRemoteControlStop:
            [controller playMovie];
            break;
        case UIEventSubtypeRemoteControlPause:
            [controller pausePlayback];
            break;
        case UIEventSubtypeRemoteControlTogglePlayPause:
            [controller togglePlayPause];
            break;
        case UIEventSubtypeRemoteControlNextTrack:
            [controller nextTrack];
            break;
        case UIEventSubtypeRemoteControlPreviousTrack:
            [controller previousTrack];
            break;
        case UIEventSubtypeRemoteControlBeginSeekingForward:
        case UIEventSubtypeRemoteControlEndSeekingForward:
        case UIEventSubtypeRemoteControlBeginSeekingBackward:
        case UIEventSubtypeRemoteControlEndSeekingBackward:
            break;
        default:
            break;
    }
}

@end
