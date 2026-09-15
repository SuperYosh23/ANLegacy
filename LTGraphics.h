#import <UIKit/UIKit.h>

@interface LTGraphics : NSObject

+ (void)loadFARegisteredFontsIfNeeded;
+ (UIFont *)fontAwesomeFontWithSize:(CGFloat)size;

+ (UIImage *)homeIcon;
+ (UIImage *)searchIcon;
+ (UIImage *)popularIcon;
+ (UIImage *)settingsIcon;
+ (UIImage *)libraryIcon;

+ (UIImage *)playIcon;
+ (UIImage *)shuffleIcon;
+ (UIImage *)downloadIcon;
+ (UIImage *)checkmarkIcon;
+ (UIImage *)renameIcon;

+ (UIImage *)blurredImageFromImage:(UIImage *)image;

@end
