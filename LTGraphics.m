#import "LTGraphics.h"

@implementation LTGraphics

static BOOL LTFAFontLoaded = NO;

+ (void)loadFARegisteredFontsIfNeeded {
    if (LTFAFontLoaded) return;
    NSArray *names = @[
        @"FontAwesome6Free-Solid",
        @"Font Awesome 6 Free",
        @"FontAwesome5Free-Solid",
        @"Font Awesome 5 Free",
        @"FontAwesome",
    ];
    for (NSString *name in names) {
        UIFont *f = [UIFont fontWithName:name size:14];
        if (f) {
            LTFAFontLoaded = YES;
            break;
        }
    }
}

+ (UIFont *)fontAwesomeFontWithSize:(CGFloat)size {
    NSArray *names = @[
        @"FontAwesome6Free-Solid",
        @"Font Awesome 6 Free",
        @"FontAwesome5Free-Solid",
        @"Font Awesome 5 Free",
        @"FontAwesome",
    ];
    for (NSString *name in names) {
        UIFont *font = [UIFont fontWithName:name size:size];
        if (font) return font;
    }
    return nil;
}

+ (UIImage *)iconWithDrawing:(void (^)(CGContextRef context))drawing {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (drawing) drawing(ctx);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)glyphIcon:(unichar)glyph {
    [self loadFARegisteredFontsIfNeeded];
    UIFont *font = [self fontAwesomeFontWithSize:30];
    if (!font) return nil;
    NSString *string = [NSString stringWithFormat:@"%C", glyph];
    CGSize stringSize = [string sizeWithFont:font];
    CGFloat scale = 0.0f;
    if (stringSize.width > 0 && stringSize.height > 0) {
        scale = MIN(30.0f / stringSize.width, 30.0f / stringSize.height);
    }
    if (scale < 1.0f) {
        font = [UIFont fontWithName:font.fontName size:30.0f * scale];
        if (font) {
            stringSize = [string sizeWithFont:font];
        }
    }
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
    CGPoint origin = CGPointMake((30.0f - stringSize.width) / 2.0f,
                                 (30.0f - stringSize.height) / 2.0f);
    [string drawAtPoint:origin withFont:font];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)homeIcon {
    UIImage *glyph = [self glyphIcon:0xF015];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor whiteColor] setFill];
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(7, 13, 16, 11)]];
        [path moveToPoint:CGPointMake(15, 4)];
        [path addLineToPoint:CGPointMake(25, 14)];
        [path addLineToPoint:CGPointMake(5, 14)];
        [path closePath];
        [path fill];
    }];
}

+ (UIImage *)searchIcon {
    UIImage *glyph = [self glyphIcon:0xF002];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor whiteColor] setStroke];
        UIBezierPath *lens = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(5, 5, 15, 15)];
        lens.lineWidth = 2.5f;
        [lens stroke];
        UIBezierPath *handle = [UIBezierPath bezierPath];
        [handle moveToPoint:CGPointMake(18, 18)];
        [handle addLineToPoint:CGPointMake(25, 25)];
        handle.lineWidth = 3.5f;
        handle.lineCapStyle = kCGLineCapRound;
        [handle stroke];
    }];
}

+ (UIImage *)popularIcon {
    UIImage *glyph = [self glyphIcon:0xF06D];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor whiteColor] setFill];
        UIBezierPath *star = [UIBezierPath bezierPath];
        CGPoint c = CGPointMake(15, 15);
        CGFloat outer = 9.0f;
        CGFloat inner = 4.0f;
        for (int i = 0; i < 10; i++) {
            CGFloat radius = (i % 2 == 0) ? outer : inner;
            CGFloat angle = -M_PI_2 + i * M_PI / 5.0;
            CGPoint p = CGPointMake(c.x + radius * cos(angle), c.y + radius * sin(angle));
            if (i == 0) [star moveToPoint:p];
            else [star addLineToPoint:p];
        }
        [star closePath];
        [star fill];
    }];
}

+ (UIImage *)settingsIcon {
    UIImage *glyph = [self glyphIcon:0xF013];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor whiteColor] setStroke];
        UIBezierPath *lines = [UIBezierPath bezierPath];
        [lines moveToPoint:CGPointMake(5, 8)];
        [lines addLineToPoint:CGPointMake(25, 8)];
        [lines moveToPoint:CGPointMake(5, 15)];
        [lines addLineToPoint:CGPointMake(25, 15)];
        [lines moveToPoint:CGPointMake(5, 22)];
        [lines addLineToPoint:CGPointMake(25, 22)];
        lines.lineWidth = 2.5f;
        lines.lineCapStyle = kCGLineCapRound;
        [lines stroke];

        UIBezierPath *knobs = [UIBezierPath bezierPath];
        [knobs moveToPoint:CGPointMake(11, 5.75f)];
        [knobs addLineToPoint:CGPointMake(11, 10.25f)];
        [knobs moveToPoint:CGPointMake(19, 12.75f)];
        [knobs addLineToPoint:CGPointMake(19, 17.25f)];
        [knobs moveToPoint:CGPointMake(13, 19.75f)];
        [knobs addLineToPoint:CGPointMake(13, 24.25f)];
        knobs.lineWidth = 3.0f;
        knobs.lineCapStyle = kCGLineCapRound;
        [knobs stroke];
    }];
}

@end
