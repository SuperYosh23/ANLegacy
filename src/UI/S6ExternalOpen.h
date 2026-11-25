#import <UIKit/UIKit.h>

// Opening a web link the way this family of apps does it. On iOS 6 an action sheet asks: Safari, Surfari (the
// family's browser, when installed) and, for sharing, "copy"; on iOS 7 and newer the link opens in Safari at once
// and sharing is the system sheet. A link to YouTube, Twitch, Kick or TikTok offers the sister app (Tubie, Twitcher,
// Kicker, TikTak) first when it is installed, on every iOS. A sheet's delegate keeps itself alive until it is gone.
@interface S6ExternalOpen : NSObject

+ (void)presentShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;
// Just the browser chooser (no "copy"); used where a link is being opened rather than shared
+ (void)presentOpenInForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;
// The links found in a text: one opens at once, several are listed first
+ (void)presentLinkChooserForURLs:(NSArray *)urls from:(UIViewController *)controller anchor:(UIView *)anchor;
// The web links (http, https) in a text, in order, without duplicates
+ (NSArray *)linksInText:(NSString *)text;
// Whether Surfari is installed (iOS 6 only; its URL scheme answers)
+ (BOOL)surfariAvailable;

@end
