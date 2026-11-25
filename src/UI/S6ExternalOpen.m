#import "S6ExternalOpen.h"
#import "S6Common.h"

// The iOS 7+ calls below run only after a runtime check; the SDK knows them
#pragma clang diagnostic ignored "-Wunguarded-availability"

@interface S6ExternalOpen () <UIActionSheetDelegate>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSArray *urls;      // the link chooser: one URL per button
@property (nonatomic, strong) NSArray *actions;   // the open/share sheet: "copy", "safari", "surfari" or "app:<scheme>" per button
@property (nonatomic, unsafe_unretained) UIViewController *controller;
@property (nonatomic, unsafe_unretained) UIView *anchor;
@end

// The live sheets' delegates, so ARC does not free them while a sheet is on screen
static NSMutableArray *g_live;

static BOOL S6ModernOS(void)
{
    return [[UIDevice currentDevice].systemVersion floatValue] >= 7.0f;
}

static NSString *S6PercentEncode(NSString *s)
{
    CFStringRef r = CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)(s ?: @""), NULL,
                                                            CFSTR(":/?#[]@!$&'()*+,;="), kCFStringEncodingUTF8);
    return (__bridge_transfer NSString *)r;
}

static NSString *S6ShortURL(NSString *s)
{
    if ([s hasPrefix:@"https://"]) s = [s substringFromIndex:8];
    else if ([s hasPrefix:@"http://"]) s = [s substringFromIndex:7];
    if (s.length > 60) s = [[s substringToIndex:57] stringByAppendingString:@"..."];
    return s;
}

// The sister apps of this family and the sites each opens (through <scheme>:open?url=<link>)
static NSArray *S6SisterApps(void)
{
    return @[
        @{ @"name": @"Tubie",    @"scheme": @"tubie",    @"hosts": @[ @"youtube.com", @"youtu.be" ] },
        @{ @"name": @"Twitcher", @"scheme": @"twitcher", @"hosts": @[ @"twitch.tv" ] },
        @{ @"name": @"Kicker",   @"scheme": @"kicker",   @"hosts": @[ @"kick.com" ] },
        @{ @"name": @"TikTak",   @"scheme": @"tiktak",   @"hosts": @[ @"tiktok.com" ] },
    ];
}

static BOOL S6HostMatches(NSString *host, NSArray *hosts)
{
    host = [host lowercaseString];
    for (NSString *h in hosts) {
        if ([host isEqualToString:h] || [host hasSuffix:[@"." stringByAppendingString:h]]) return YES;
    }
    return NO;
}

@implementation S6ExternalOpen

+ (BOOL)surfariAvailable
{
    if (S6ModernOS()) return NO;   // Surfari is a browser for iOS 6
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"surfari://open?url=https://example.com/"]];
}

+ (NSURL *)surfariURLForURL:(NSURL *)url
{
    return [NSURL URLWithString:[@"surfari://open?url=" stringByAppendingString:S6PercentEncode(url.absoluteString)]];
}

+ (NSArray *)sisterAppsForURL:(NSURL *)url
{
    NSMutableArray *apps = [NSMutableArray array];
    if (!url.host.length) return apps;
    UIApplication *app = [UIApplication sharedApplication];
    for (NSDictionary *sister in S6SisterApps()) {
        if ([[sister objectForKey:@"name"] isEqualToString:@"Sixify"]) continue;
        if (!S6HostMatches(url.host, [sister objectForKey:@"hosts"])) continue;
        if (![app canOpenURL:[NSURL URLWithString:[[sister objectForKey:@"scheme"] stringByAppendingString:@":open"]]]) continue;
        [apps addObject:sister];
    }
    return apps;
}

+ (NSArray *)linksInText:(NSString *)text
{
    NSMutableArray *urls = [NSMutableArray array];
    if (!text.length) return urls;
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL];
    [detector enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                            usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        NSURL *url = match.URL;
        if (![[url.scheme lowercaseString] hasPrefix:@"http"]) return;   // (a bare domain comes back as http)
        for (NSURL *u in urls) if ([u.absoluteString isEqualToString:url.absoluteString]) return;
        [urls addObject:url];
    }];
    return urls;
}

+ (void)presentShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    [self present:url copy:YES from:controller anchor:anchor];
}

+ (void)presentOpenInForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    [self present:url copy:NO from:controller anchor:anchor];
}

+ (void)presentLinkChooserForURLs:(NSArray *)urls from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (urls.count == 0) return;
    if (urls.count == 1) { [self present:urls[0] copy:NO from:controller anchor:anchor]; return; }
    S6ExternalOpen *open = [[S6ExternalOpen alloc] init];
    open.urls = urls;
    open.controller = controller;
    open.anchor = anchor;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Open Link") delegate:open cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSURL *u in urls) [sheet addButtonWithTitle:S6ShortURL(u.absoluteString)];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    [self show:sheet delegate:open from:controller anchor:anchor];
}

+ (void)show:(UIActionSheet *)sheet delegate:(S6ExternalOpen *)open from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!g_live) g_live = [NSMutableArray array];
    [g_live addObject:open];
    BOOL pad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    if (pad && anchor) [sheet showFromRect:anchor.bounds inView:anchor animated:YES];
    else [sheet showInView:controller.view ?: [UIApplication sharedApplication].keyWindow];
}

+ (void)present:(NSURL *)url copy:(BOOL)copy from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!url || ![[url.scheme lowercaseString] hasPrefix:@"http"]) return;
    NSArray *sisters = [self sisterAppsForURL:url];
    BOOL modern = S6ModernOS();
    NSLog(@"[Sixify] link %@: %@, %lu sister app(s)%@", copy ? @"share" : @"open", url.absoluteString, (unsigned long)sisters.count,
          modern ? @"" : ([self surfariAvailable] ? @", Surfari" : @", no Surfari"));
    if (modern && copy) { [self presentActivitySheetForURL:url from:controller anchor:anchor]; return; }
    if (modern && sisters.count == 0) { [[UIApplication sharedApplication] openURL:url]; return; }

    S6ExternalOpen *open = [[S6ExternalOpen alloc] init];
    open.url = url;
    NSMutableArray *actions = [NSMutableArray array];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:url.absoluteString delegate:open cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSDictionary *sister in sisters) {
        [sheet addButtonWithTitle:[NSString stringWithFormat:L(@"Open in %@"), [sister objectForKey:@"name"]]];
        [actions addObject:[@"app:" stringByAppendingString:[sister objectForKey:@"scheme"]]];
    }
    if (copy) { [sheet addButtonWithTitle:L(@"Copy link")]; [actions addObject:@"copy"]; }
    [sheet addButtonWithTitle:L(@"Open in Safari")];
    [actions addObject:@"safari"];
    if ([self surfariAvailable]) { [sheet addButtonWithTitle:L(@"Open in Surfari")]; [actions addObject:@"surfari"]; }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    open.actions = actions;
    [self show:sheet delegate:open from:controller anchor:anchor];
}

// iOS 7 and newer: the system share sheet
+ (void)presentActivitySheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
    if (!controller) { [[UIApplication sharedApplication] openURL:url]; return; }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && [activity respondsToSelector:@selector(popoverPresentationController)]) {
        UIPopoverPresentationController *pop = activity.popoverPresentationController;
        pop.sourceView = anchor ?: controller.view;
        pop.sourceRect = anchor ? anchor.bounds : CGRectMake(CGRectGetMidX(controller.view.bounds), CGRectGetMaxY(controller.view.bounds) - 1, 1, 1);
    }
    [controller presentViewController:activity animated:YES completion:nil];
#else
    [[UIApplication sharedApplication] openURL:url];
#endif
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex >= 0 && buttonIndex != actionSheet.cancelButtonIndex) {
        UIApplication *app = [UIApplication sharedApplication];
        if (self.urls) {   // the link chooser: the picked link goes through the open sheet (after this one is gone)
            if ((NSUInteger)buttonIndex < self.urls.count) {
                NSURL *u = self.urls[(NSUInteger)buttonIndex];
                UIViewController *controller = self.controller;
                UIView *anchor = self.anchor;
                dispatch_async(dispatch_get_main_queue(), ^{ [S6ExternalOpen present:u copy:NO from:controller anchor:anchor]; });
            }
        } else if ((NSUInteger)buttonIndex < self.actions.count) {
            NSString *action = self.actions[(NSUInteger)buttonIndex];
            if ([action isEqualToString:@"copy"]) [UIPasteboard generalPasteboard].string = self.url.absoluteString;
            else if ([action isEqualToString:@"safari"]) [app openURL:self.url];
            else if ([action isEqualToString:@"surfari"]) [app openURL:[S6ExternalOpen surfariURLForURL:self.url]];
            else if ([action hasPrefix:@"app:"]) {
                NSString *scheme = [action substringFromIndex:4];
                [app openURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@:open?url=%@", scheme, S6PercentEncode(self.url.absoluteString)]]];
            }
        }
    }
    [g_live removeObject:self];
}

@end
