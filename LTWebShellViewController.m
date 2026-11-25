#import "LTWebShellViewController.h"
#import "LTWebServer.h"
#import "LTWebAPI.h"
#import "LTTheme.h"
#import "LTLog.h"

// WebKit's API is declared by hand - see LTWebKitShim.h for why the SDK's
// headers cannot be imported.
#import "LTWebKitShim.h"

// The port the embedded server listens on. Matches the desktop backend's port
// so the same bundle works in both places.
static const NSInteger kLTWebPort = 3614;

@interface LTWebShellViewController ()
@property (nonatomic, strong) LTWebServer *server;
@property (nonatomic, strong) id webView;
@property (nonatomic, strong) LTWebAPI *api;
@end

@implementation LTWebShellViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    // WKWebView is unavailable on iOS 4-7; the web shell is not available on those versions.
    if (!NSClassFromString(@"WKWebView")) {
        UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
        label.text = @"Web view is not available on this version of iOS.";
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor whiteColor];
        label.numberOfLines = 0;
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:label];
        return;
    }

    self.api = [[LTWebAPI alloc] init];

    // Serve the bundled web app.
    NSString *root = [[NSBundle mainBundle] pathForResource:@"webapp" ofType:nil];
    if (!root) {
        // The bundle resource is missing; say so rather than showing a blank
        // screen, because a blank screen gives no clue what went wrong.
        UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
        label.text = @"Web app missing from bundle";
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor whiteColor];
        label.numberOfLines = 0;
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view addSubview:label];
        return;
    }

    self.server = [[LTWebServer alloc] init];
    self.server.staticRoot = root;
    self.server.api = self.api;
    self.server.fileProvider = self.api;
    if (![self.server startOnPort:kLTWebPort]) {
        LTLog(@"WEB shell could not start server");
    }

    Class configClass = NSClassFromString(@"WKWebViewConfiguration");
    id config = configClass ? [[configClass alloc] init] : nil;
    // Media playback without a user gesture is blocked by default, and the
    // player starts a track as soon as it is chosen.
    [config setValue:@YES forKey:@"allowsInlineMediaPlayback"];
    // iOS 10 and later only; setting it on iOS 9 would be an unrecognised
    // selector.
    SEL selector = @selector(setMediaTypesRequiringUserActionForPlayback:);
    if ([config respondsToSelector:selector]) {
        [config setValue:@(LTWKAudiovisualMediaTypeNone) forKey:@"mediaTypesRequiringUserActionForPlayback"];
    }

    Class webClass = NSClassFromString(@"WKWebView");
    self.webView = webClass ? [[webClass alloc] initWithFrame:self.view.bounds configuration:config] : nil;
    [self.webView setValue:@(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight) forKey:@"autoresizingMask"];
    [self.webView setValue:[UIColor blackColor] forKey:@"backgroundColor"];
    [[self.webView valueForKey:@"scrollView"] setValue:@NO forKey:@"bounces"];
    [self.view addSubview:self.webView];

    // The page is told it is on a phone, and which theme it should use, with
    // query parameters rather than a script: evaluateJavaScript: after
    // loadRequest: runs against the previous page's context, so a flag set that
    // way is gone by the time the new page runs its first script.
    NSString *theme = self.darkAppearance ? @"dark" : @"light";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%ld/?mobile=1&theme=%@", (long)kLTWebPort, theme]];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self applyAppearance];
}

// The web app picks its palette from a data-theme attribute on the root
// element, and it reads the theme out of the query string when the page loads.
// This re-applies it for the case where the page has already loaded and the
// theme changes underneath it.
- (void)applyAppearance {
    if (!self.webView) return;
    NSString *js = self.darkAppearance
        ? @"document.documentElement.setAttribute('data-theme','dark');"
        : @"document.documentElement.setAttribute('data-theme','light');";
    [self.webView evaluateJavaScript:js completionHandler:nil];
}

- (void)setDarkAppearance:(BOOL)darkAppearance {
    _darkAppearance = darkAppearance;
    [self applyAppearance];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)dealloc {
    [self.server stop];
}

@end
