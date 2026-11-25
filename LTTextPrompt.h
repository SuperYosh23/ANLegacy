#import <UIKit/UIKit.h>

// Presents a single-line text prompt. Uses UIAlertView's plain-text style on
// iOS 5+, and falls back to a simple modal controller on iOS 4.x where that
// style does not exist.
@interface LTTextPrompt : NSObject
+ (void)presentIn:(UIViewController *)presenter
             title:(NSString *)title
           message:(NSString *)message
       placeholder:(NSString *)placeholder
       initialText:(NSString *)initialText
        completion:(void (^)(NSString *text, BOOL cancelled))completion;
@end
