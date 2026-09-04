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
    return [self coloredGlyphIcon:glyph color:[UIColor whiteColor]];
}

+ (UIImage *)coloredGlyphIcon:(unichar)glyph color:(UIColor *)color {
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
    [color setFill];
    CGPoint origin = CGPointMake((30.0f - stringSize.width) / 2.0f,
                                 (30.0f - stringSize.height) / 2.0f);
    [string drawAtPoint:origin withFont:font];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

+ (UIImage *)playIcon {
    UIImage *glyph = [self coloredGlyphIcon:0xF04B color:[UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f]];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor blueColor] setFill];
        UIBezierPath *tri = [UIBezierPath bezierPath];
        [tri moveToPoint:CGPointMake(9, 6)];
        [tri addLineToPoint:CGPointMake(24, 15)];
        [tri addLineToPoint:CGPointMake(9, 24)];
        [tri closePath];
        [tri fill];
    }];
}

+ (UIImage *)shuffleIcon {
    UIImage *glyph = [self coloredGlyphIcon:0xF074 color:[UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f]];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor blueColor] setStroke];
        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(5, 7)];
        [p addLineToPoint:CGPointMake(12, 7)];
        p.lineWidth = 2.5f; p.lineCapStyle = kCGLineCapRound; [p stroke];
    }];
}

+ (UIImage *)downloadIcon {
    UIImage *glyph = [self coloredGlyphIcon:0xF019 color:[UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f]];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor blueColor] setStroke];
        UIBezierPath *arrow = [UIBezierPath bezierPath];
        [arrow moveToPoint:CGPointMake(15, 5)];
        [arrow addLineToPoint:CGPointMake(15, 19)];
        arrow.lineWidth = 3.0f; arrow.lineCapStyle = kCGLineCapRound; [arrow stroke];
        UIBezierPath *head = [UIBezierPath bezierPath];
        [head moveToPoint:CGPointMake(9, 13)];
        [head addLineToPoint:CGPointMake(15, 20)];
        [head addLineToPoint:CGPointMake(21, 13)];
        head.lineWidth = 3.0f; head.lineCapStyle = kCGLineCapRound; [head stroke];
        UIBezierPath *base = [UIBezierPath bezierPath];
        [base moveToPoint:CGPointMake(6, 24)];
        [base addLineToPoint:CGPointMake(24, 24)];
        base.lineWidth = 3.0f; base.lineCapStyle = kCGLineCapRound; [base stroke];
    }];
}

+ (UIImage *)checkmarkIcon {
    UIImage *glyph = [self coloredGlyphIcon:0xF00C color:[UIColor colorWithRed:0.20f green:0.72f blue:0.30f alpha:1.0f]];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor colorWithRed:0.20f green:0.72f blue:0.30f alpha:1.0f] setStroke];
        UIBezierPath *check = [UIBezierPath bezierPath];
        [check moveToPoint:CGPointMake(6, 16)];
        [check addLineToPoint:CGPointMake(13, 23)];
        [check addLineToPoint:CGPointMake(25, 8)];
        check.lineWidth = 4.0f;
        check.lineCapStyle = kCGLineCapRound;
        check.lineJoinStyle = kCGLineJoinRound;
        [check stroke];
    }];
}

+ (UIImage *)renameIcon {
    UIImage *glyph = [self coloredGlyphIcon:0xF303 color:[UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f]];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor blueColor] setStroke];
        UIBezierPath *pencil = [UIBezierPath bezierPath];
        [pencil moveToPoint:CGPointMake(6, 24)];
        [pencil addLineToPoint:CGPointMake(8, 17)];
        [pencil addLineToPoint:CGPointMake(20, 5)];
        [pencil addLineToPoint:CGPointMake(25, 10)];
        [pencil addLineToPoint:CGPointMake(13, 22)];
        [pencil closePath];
        pencil.lineWidth = 2.5f; pencil.lineCapStyle = kCGLineCapRound; [pencil stroke];
    }];
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

+ (UIImage *)libraryIcon {
    UIImage *glyph = [self glyphIcon:0xF5FD];
    if (glyph) return glyph;
    return [self iconWithDrawing:^(CGContextRef ctx) {
        [[UIColor whiteColor] setFill];

        CGFloat shelfTop = 22.5f;
        UIBezierPath *shelf = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(4.5f, shelfTop, 21.0f, 2.5f) cornerRadius:1.25f];
        [shelf fill];

        UIBezierPath *smallBook = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(6.0f, 9.5f, 4.5f, 12.0f) cornerRadius:1.0f];
        [smallBook fill];

        UIBezierPath *tallBook = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(12.0f, 4.5f, 4.5f, 17.0f) cornerRadius:1.0f];
        [tallBook fill];

        UIBezierPath *midBook = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(18.5f, 7.0f, 4.5f, 14.5f) cornerRadius:1.0f];
        [midBook fill];

        [[UIColor colorWithWhite:0.65f alpha:1.0f] setStroke];
        UIBezierPath *spines = [UIBezierPath bezierPath];
        [spines moveToPoint:CGPointMake(8.25f, 10.5f)];
        [spines addLineToPoint:CGPointMake(8.25f, 20.5f)];
        [spines moveToPoint:CGPointMake(14.25f, 5.5f)];
        [spines addLineToPoint:CGPointMake(14.25f, 20.5f)];
        [spines moveToPoint:CGPointMake(20.75f, 8.0f)];
        [spines addLineToPoint:CGPointMake(20.75f, 20.5f)];
        spines.lineWidth = 1.5f;
        spines.lineCapStyle = kCGLineCapRound;
        [spines stroke];
    }];
}

+ (UIImage *)blurredImageFromImage:(UIImage *)image {
    CGImageRef cgSrc = image.CGImage;
    if (!cgSrc) return nil;

    size_t srcW = CGImageGetWidth(cgSrc);
    size_t srcH = CGImageGetHeight(cgSrc);
    if (srcW < 2 || srcH < 2) return nil;

    size_t maxDim = 100;
    CGFloat ratio = (CGFloat)maxDim / MAX(srcW, srcH);
    if (ratio > 1.0f) ratio = 1.0f;
    size_t w = (size_t)MAX(2, (size_t)roundf(srcW * ratio));
    size_t h = (size_t)MAX(2, (size_t)roundf(srcH * ratio));

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    uint8_t *buf = (uint8_t *)calloc(w * h * 4, 1);
    CGContextRef ctx = CGBitmapContextCreate(buf, w, h, 8, w * 4, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(buf); return nil; }

    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cgSrc);
    CGContextRelease(ctx);

    size_t radius = (size_t)MAX(3, (size_t)(MIN(w, h) * 0.15));
    uint8_t *tmp = (uint8_t *)calloc(w * h * 4, 1);
    int passes = 3;

    for (int p = 0; p < passes; p++) {
        for (size_t y = 0; y < h; y++) {
            for (size_t x = 0; x < w; x++) {
                int32_t sR=0, sG=0, sB=0, sA=0;
                int cnt = 0;
                for (int d = -(int)radius; d <= (int)radius; d++) {
                    size_t sx = x + d;
                    if (sx >= w) continue;
                    size_t i = (y * w + sx) * 4;
                    sR += buf[i]; sG += buf[i+1]; sB += buf[i+2]; sA += buf[i+3];
                    cnt++;
                }
                size_t i = (y * w + x) * 4;
                tmp[i]   = (uint8_t)(sR / cnt);
                tmp[i+1] = (uint8_t)(sG / cnt);
                tmp[i+2] = (uint8_t)(sB / cnt);
                tmp[i+3] = (uint8_t)(sA / cnt);
            }
        }
        for (size_t y = 0; y < h; y++) {
            for (size_t x = 0; x < w; x++) {
                int32_t sR=0, sG=0, sB=0, sA=0;
                int cnt = 0;
                for (int d = -(int)radius; d <= (int)radius; d++) {
                    size_t sy = y + d;
                    if (sy >= h) continue;
                    size_t i = (sy * w + x) * 4;
                    sR += tmp[i]; sG += tmp[i+1]; sB += tmp[i+2]; sA += tmp[i+3];
                    cnt++;
                }
                size_t i = (y * w + x) * 4;
                buf[i]   = (uint8_t)(sR / cnt);
                buf[i+1] = (uint8_t)(sG / cnt);
                buf[i+2] = (uint8_t)(sB / cnt);
                buf[i+3] = (uint8_t)(sA / cnt);
            }
        }
    }
    free(tmp);

    CGColorSpaceRef cs2 = CGColorSpaceCreateDeviceRGB();
    CGContextRef outCtx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, cs2,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
    CGColorSpaceRelease(cs2);
    if (!outCtx) { free(buf); return nil; }
    memcpy(CGBitmapContextGetData(outCtx), buf, w * h * 4);
    CGImageRef cgOut = CGBitmapContextCreateImage(outCtx);
    CGContextRelease(outCtx);
    free(buf);
    UIImage *result = [UIImage imageWithCGImage:cgOut];
    CGImageRelease(cgOut);
    return result;
}

@end
