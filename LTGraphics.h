#import <UIKit/UIKit.h>

@interface LTGraphics : NSObject

+ (void)loadFARegisteredFontsIfNeeded;
+ (UIFont *)fontAwesomeFontWithSize:(CGFloat)size;

+ (void)registerBundledFontsIfNeeded;
+ (UIImage *)glyphIcon:(unichar)glyph size:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)repeatIconOfSize:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)repeatOneIconOfSize:(CGFloat)size color:(UIColor *)color;

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

// Up to `count` representative colors of an image, brightest-normalized so they
// work as glow tints. Never returns empty for a usable image.
+ (NSArray *)dominantColorsFromImage:(UIImage *)image count:(NSUInteger)count;

@end
