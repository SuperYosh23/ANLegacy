#import "S6Theme.h"
#import <objc/message.h>
#import "S6Modern.h"
#import "S6Common.h"

static UIColor *RGB(NSInteger r, NSInteger g, NSInteger b)
{
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1.0];
}

static void S6DrawVerticalGradient(CGContextRef ctx, CGRect rect, UIColor *top, UIColor *bottom)
{
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (id)top.CGColor, (id)bottom.CGColor ];
    CGFloat locations[2] = { 0.0, 1.0 };
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(rect.origin.x, CGRectGetMinY(rect)), CGPointMake(rect.origin.x, CGRectGetMaxY(rect)), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

static UIImage *S6DrawImage(CGSize size, BOOL opaque, void (^draw)(CGContextRef ctx))
{
    UIGraphicsBeginImageContextWithOptions(size, opaque, 0);
    draw(UIGraphicsGetCurrentContext());
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

// A rounded, vertically shaded button face with an optional gloss, stretchable
static UIImage *S6ButtonImage(UIColor *top, UIColor *bottom, UIColor *stroke, CGFloat radius, BOOL gloss, BOOL pressed)
{
    CGFloat side = radius * 2 + 4;
    UIImage *image = S6DrawImage(CGSizeMake(side, side), NO, ^(CGContextRef ctx) {
        CGRect r = CGRectMake(0.5, 0.5, side - 1, side - 1);
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius - 0.5];
        CGContextSaveGState(ctx);
        [path addClip];
        S6DrawVerticalGradient(ctx, r, pressed ? bottom : top, pressed ? top : bottom);
        if (gloss && !pressed) {
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1 alpha:0.16].CGColor);
            CGContextFillRect(ctx, CGRectMake(0, 0, side, floor(side / 2)));
        }
        CGContextRestoreGState(ctx);
        if (stroke) {
            [stroke setStroke];
            path.lineWidth = 1;
            [path stroke];
        }
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(radius + 1, radius + 1, radius + 1, radius + 1) resizingMode:UIImageResizingModeStretch];
}

static UIImage *S6BarImage(UIColor *top, UIColor *bottom, UIColor *highlight, UIColor *line, CGFloat height)
{
    UIImage *image = S6DrawImage(CGSizeMake(4, height), YES, ^(CGContextRef ctx) {
        S6DrawVerticalGradient(ctx, CGRectMake(0, 0, 4, height), top, bottom);
        [highlight setFill];
        UIRectFill(CGRectMake(0, 0, 4, 1));
        [line setFill];
        UIRectFill(CGRectMake(0, height - 1, 4, 1));
    });
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(2, 1, 2, 1) resizingMode:UIImageResizingModeStretch];
}

@interface S6Theme ()
@property (nonatomic, strong) NSMutableDictionary *cache;
@end

@implementation S6Theme

+ (instancetype)shared
{
    static S6Theme *theme;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ theme = [[S6Theme alloc] init]; });
    return theme;
}

- (instancetype)init
{
    if ((self = [super init])) _cache = [NSMutableDictionary dictionary];
    return self;
}

- (id)cached:(NSString *)key build:(id (^)(void))build
{
    id v = self.cache[key];
    if (!v) {
        v = build();
        if (v) self.cache[key] = v;
    }
    return v;
}

#pragma mark - Colours

- (UIColor *)plainBackgroundColor { return RGB(30, 31, 33); }

- (UIColor *)backgroundColor
{
    // a faint grain, as the panels of 2012 had
    return [self cached:@"bg" build:^id {
        UIImage *noise = S6DrawImage(CGSizeMake(64, 64), YES, ^(CGContextRef ctx) {
            [RGB(30, 31, 33) setFill];
            UIRectFill(CGRectMake(0, 0, 64, 64));
            srand48(6);
            for (int i = 0; i < 1400; i++) {
                CGFloat w = drand48() < 0.5 ? 1 : 0;
                [[UIColor colorWithWhite:w alpha:0.025 + drand48() * 0.03] setFill];
                UIRectFill(CGRectMake(floor(drand48() * 64), floor(drand48() * 64), 1, 1));
            }
        });
        return [UIColor colorWithPatternImage:noise];
    }];
}

- (UIColor *)panelColor { return RGB(40, 41, 44); }
- (UIColor *)rowColor { return [UIColor clearColor]; }
- (UIColor *)rowHighlightColor { return RGB(56, 58, 62); }
- (UIColor *)primaryTextColor { return RGB(238, 238, 238); }
- (UIColor *)secondaryTextColor { return RGB(150, 151, 154); }
- (UIColor *)tertiaryTextColor { return RGB(105, 106, 110); }
- (UIColor *)separatorColor { return RGB(48, 49, 52); }
- (UIColor *)accentColor { return RGB(132, 189, 0); }
- (UIColor *)accentTextColor { return RGB(146, 200, 30); }

#pragma mark - Artwork

- (UIImage *)navigationBarImage
{
    return [self cached:@"nav" build:^id { return S6BarImage(RGB(58, 59, 62), RGB(22, 22, 24), [UIColor colorWithWhite:1 alpha:0.18], RGB(5, 5, 6), 44); }];
}

- (UIImage *)playerBarImage
{
    return [self cached:@"player" build:^id { return S6BarImage(RGB(50, 51, 54), RGB(26, 27, 29), [UIColor colorWithWhite:1 alpha:0.16], RGB(10, 10, 11), 72); }];
}

- (UIImage *)tabBarImage
{
    return [self cached:@"tab" build:^id { return S6BarImage(RGB(44, 45, 48), RGB(16, 16, 18), [UIColor colorWithWhite:1 alpha:0.15], RGB(0, 0, 0), 49); }];
}

- (UIImage *)greenButtonImageHighlighted:(BOOL)highlighted
{
    return [self cached:highlighted ? @"green-h" : @"green" build:^id {
        return S6ButtonImage(RGB(150, 206, 22), RGB(104, 156, 0), RGB(70, 110, 0), 15, YES, highlighted);
    }];
}

- (UIImage *)darkButtonImageHighlighted:(BOOL)highlighted
{
    return [self cached:highlighted ? @"dark-h" : @"dark" build:^id {
        return S6ButtonImage(RGB(72, 73, 77), RGB(40, 41, 44), RGB(16, 16, 18), 5, YES, highlighted);
    }];
}

- (UIImage *)outlineButtonImageHighlighted:(BOOL)highlighted
{
    return [self cached:highlighted ? @"outline-h" : @"outline" build:^id {
        CGFloat side = 34;
        UIImage *image = S6DrawImage(CGSizeMake(side, side), NO, ^(CGContextRef ctx) {
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(1, 1, side - 2, side - 2) cornerRadius:15];
            if (highlighted) { [[UIColor colorWithWhite:1 alpha:0.12] setFill]; [path fill]; }
            [[UIColor colorWithWhite:1 alpha:0.55] setStroke];
            path.lineWidth = 1.5;
            [path stroke];
        });
        return [image resizableImageWithCapInsets:UIEdgeInsetsMake(16, 16, 16, 16) resizingMode:UIImageResizingModeStretch];
    }];
}

- (UIImage *)searchFieldImage
{
    return [self cached:@"search" build:^id {
        UIImage *image = S6DrawImage(CGSizeMake(32, 30), NO, ^(CGContextRef ctx) {
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.5, 0.5, 31, 29) cornerRadius:14.5];
            [RGB(16, 16, 17) setFill];
            [path fill];
            [[UIColor colorWithWhite:1 alpha:0.12] setStroke];
            [path stroke];
        });
        return [image resizableImageWithCapInsets:UIEdgeInsetsMake(14, 15, 14, 15) resizingMode:UIImageResizingModeStretch];
    }];
}

- (UIImage *)sidebarSelectionImage
{
    return [self cached:@"sidesel" build:^id {
        UIImage *image = S6DrawImage(CGSizeMake(8, 40), YES, ^(CGContextRef ctx) {
            S6DrawVerticalGradient(ctx, CGRectMake(0, 0, 8, 40), RGB(64, 66, 70), RGB(48, 50, 54));
            [self.accentColor setFill];
            UIRectFill(CGRectMake(0, 0, 3, 40));
        });
        return [image resizableImageWithCapInsets:UIEdgeInsetsMake(1, 4, 1, 1) resizingMode:UIImageResizingModeStretch];
    }];
}

- (UIImage *)sectionHeaderImage
{
    return [self cached:@"section" build:^id { return S6BarImage(RGB(44, 45, 48), RGB(34, 35, 38), [UIColor colorWithWhite:1 alpha:0.08], RGB(20, 20, 22), 24); }];
}

- (UIImage *)artPlaceholderWithSize:(CGFloat)size
{
    NSString *key = [NSString stringWithFormat:@"art-%.0f", size];
    return [self cached:key build:^id {
        return S6DrawImage(CGSizeMake(size, size), YES, ^(CGContextRef ctx) {
            S6DrawVerticalGradient(ctx, CGRectMake(0, 0, size, size), RGB(58, 60, 64), RGB(36, 37, 40));
            UIImage *note = [self icon:S6IconAlbum size:size * 0.42 color:[UIColor colorWithWhite:1 alpha:0.18]];
            [note drawAtPoint:CGPointMake((size - note.size.width) / 2, (size - note.size.height) / 2)];
        });
    }];
}

- (UIImage *)artistPlaceholderWithSize:(CGFloat)size
{
    NSString *key = [NSString stringWithFormat:@"artist-%.0f", size];
    return [self cached:key build:^id {
        return S6DrawImage(CGSizeMake(size, size), NO, ^(CGContextRef ctx) {
            UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)];
            [RGB(52, 54, 58) setFill];
            [circle fill];
            UIImage *person = [self icon:S6IconArtist size:size * 0.5 color:[UIColor colorWithWhite:1 alpha:0.2]];
            [person drawAtPoint:CGPointMake((size - person.size.width) / 2, (size - person.size.height) / 2)];
        });
    }];
}

- (UIImage *)shadowImageTop:(BOOL)top
{
    return [self cached:top ? @"shadow-top" : @"shadow-bottom" build:^id {
        UIImage *image = S6DrawImage(CGSizeMake(4, 64), NO, ^(CGContextRef ctx) {
            UIColor *dark = [UIColor colorWithWhite:0 alpha:0.75], *clear = [UIColor colorWithWhite:0 alpha:0];
            S6DrawVerticalGradient(ctx, CGRectMake(0, 0, 4, 64), top ? dark : clear, top ? clear : dark);
        });
        return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 1, 0, 1) resizingMode:UIImageResizingModeStretch];
    }];
}

- (UIImage *)sliderTrackImageFilled:(BOOL)filled
{
    return [self cached:filled ? @"track-on" : @"track-off" build:^id {
        UIImage *image = S6DrawImage(CGSizeMake(12, 6), NO, ^(CGContextRef ctx) {
            UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 1, 12, 4) cornerRadius:2];
            [(filled ? self.accentColor : RGB(70, 72, 76)) setFill];
            [path fill];
        });
        return [image resizableImageWithCapInsets:UIEdgeInsetsMake(0, 5, 0, 5) resizingMode:UIImageResizingModeStretch];
    }];
}

- (UIImage *)sliderThumbImage
{
    return [self cached:@"thumb" build:^id {
        return S6DrawImage(CGSizeMake(22, 22), NO, ^(CGContextRef ctx) {
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 2, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
            [[UIColor whiteColor] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(5, 4, 12, 12)] fill];
        });
    }];
}

- (UIImage *)explicitBadge
{
    return [self cached:@"explicit" build:^id {
        return S6DrawImage(CGSizeMake(14, 14), NO, ^(CGContextRef ctx) {
            [RGB(150, 151, 154) setFill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, 14, 14) cornerRadius:2] fill];
            NSString *e = @"E";
            UIFont *f = [UIFont boldSystemFontOfSize:10];
            CGSize s = [e sizeWithFont:f];
            [RGB(30, 31, 33) setFill];
            [e drawAtPoint:CGPointMake((14 - s.width) / 2, (14 - s.height) / 2) withFont:f];
        });
    }];
}

- (UIImage *)brandMarkWithSize:(CGFloat)size
{
    NSString *key = [NSString stringWithFormat:@"brand-%.0f", size];
    return [self cached:key build:^id {
        return S6DrawImage(CGSizeMake(size, size), NO, ^(CGContextRef ctx) {
            CGRect r = CGRectMake(1, 1, size - 2, size - 2);
            UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:r];
            CGContextSaveGState(ctx);
            [circle addClip];
            S6DrawVerticalGradient(ctx, r, RGB(158, 214, 30), RGB(96, 150, 0));
            // the gloss of the time over the upper half
            [[UIColor colorWithWhite:1 alpha:0.18] setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(-size * 0.25, -size * 0.55, size * 1.5, size * 1.0)] fill];
            CGContextRestoreGState(ctx);
            [RGB(60, 96, 0) setStroke];
            circle.lineWidth = 1;
            [circle stroke];
            NSString *six = @"6";
            UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:size * 0.66] ?: [UIFont boldSystemFontOfSize:size * 0.66];
            CGSize s = [six sizeWithFont:font];
            CGContextSetShadowWithColor(ctx, CGSizeMake(0, -1), 1, [UIColor colorWithWhite:0 alpha:0.35].CGColor);
            [[UIColor whiteColor] setFill];
            [six drawAtPoint:CGPointMake((size - s.width) / 2, (size - s.height) / 2) withFont:font];
        });
    }];
}

#pragma mark - Icons

static void S6Stroke(UIBezierPath *p, CGFloat width)
{
    p.lineWidth = width;
    p.lineCapStyle = kCGLineCapRound;
    p.lineJoinStyle = kCGLineJoinRound;
    [p stroke];
}

static UIBezierPath *S6Heart(void)
{
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(12, 20.5)];
    [p addCurveToPoint:CGPointMake(2.5, 9) controlPoint1:CGPointMake(6, 16) controlPoint2:CGPointMake(2.5, 13)];
    [p addCurveToPoint:CGPointMake(12, 6) controlPoint1:CGPointMake(2.5, 3.5) controlPoint2:CGPointMake(9.5, 2.5)];
    [p addCurveToPoint:CGPointMake(21.5, 9) controlPoint1:CGPointMake(14.5, 2.5) controlPoint2:CGPointMake(21.5, 3.5)];
    [p addCurveToPoint:CGPointMake(12, 20.5) controlPoint1:CGPointMake(21.5, 13) controlPoint2:CGPointMake(18, 16)];
    [p closePath];
    return p;
}

static void S6Arrowhead(CGPoint tip, CGFloat angle, CGFloat size)
{
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:tip];
    [p addLineToPoint:CGPointMake(tip.x - size * cos(angle - 0.6), tip.y - size * sin(angle - 0.6))];
    [p addLineToPoint:CGPointMake(tip.x - size * cos(angle + 0.6), tip.y - size * sin(angle + 0.6))];
    [p closePath];
    [p fill];
}

// Each icon is drawn on a 24 x 24 grid
- (void)drawIcon:(S6Icon)icon
{
    UIBezierPath *p;
    switch (icon) {
        case S6IconHome: {
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(2.5, 11.5)];
            [p addLineToPoint:CGPointMake(12, 3)];
            [p addLineToPoint:CGPointMake(21.5, 11.5)];
            S6Stroke(p, 2.2);
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(5.5, 10)];
            [p addLineToPoint:CGPointMake(5.5, 21)];
            [p addLineToPoint:CGPointMake(10, 21)];
            [p addLineToPoint:CGPointMake(10, 15)];
            [p addLineToPoint:CGPointMake(14, 15)];
            [p addLineToPoint:CGPointMake(14, 21)];
            [p addLineToPoint:CGPointMake(18.5, 21)];
            [p addLineToPoint:CGPointMake(18.5, 10)];
            S6Stroke(p, 2);
            break;
        }
        case S6IconSearch:
            S6Stroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(3.5, 3.5, 12.5, 12.5)], 2.4);
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(14.5, 14.5)];
            [p addLineToPoint:CGPointMake(20.5, 20.5)];
            S6Stroke(p, 3);
            break;
        case S6IconLibrary:
            UIRectFill(CGRectMake(3.5, 3.5, 3, 17));
            UIRectFill(CGRectMake(9, 3.5, 3, 17));
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(14, 5)];
            [p addLineToPoint:CGPointMake(17, 4)];
            [p addLineToPoint:CGPointMake(21.5, 19.5)];
            [p addLineToPoint:CGPointMake(18.5, 20.5)];
            [p closePath];
            [p fill];
            break;
        case S6IconRadio:
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(9.5, 9.5, 5, 5)] fill];
            S6Stroke([UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 12) radius:6.5 startAngle:-0.8 endAngle:0.8 clockwise:YES], 2);
            S6Stroke([UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 12) radius:6.5 startAngle:M_PI - 0.8 endAngle:M_PI + 0.8 clockwise:YES], 2);
            S6Stroke([UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 12) radius:10.5 startAngle:-0.8 endAngle:0.8 clockwise:YES], 2);
            S6Stroke([UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 12) radius:10.5 startAngle:M_PI - 0.8 endAngle:M_PI + 0.8 clockwise:YES], 2);
            break;
        case S6IconSettings: {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            for (int i = 0; i < 8; i++) {
                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, 12, 12);
                CGContextRotateCTM(ctx, i * M_PI / 4);
                CGContextFillRect(ctx, CGRectMake(-2, -11, 4, 5));
                CGContextRestoreGState(ctx);
            }
            S6Stroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(6, 6, 12, 12)], 3.5);
            break;
        }
        case S6IconBrowse:
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 3, 8, 8) cornerRadius:1.5] fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(13, 3, 8, 8) cornerRadius:1.5] fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(3, 13, 8, 8) cornerRadius:1.5] fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(13, 13, 8, 8) cornerRadius:1.5] fill];
            break;
        case S6IconPlaylist:
            UIRectFill(CGRectMake(3, 5, 12, 2));
            UIRectFill(CGRectMake(3, 10, 12, 2));
            UIRectFill(CGRectMake(3, 15, 8, 2));
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(13, 15, 5.5, 5)] fill];
            UIRectFill(CGRectMake(16.5, 4, 2, 13.5));
            UIRectFill(CGRectMake(16.5, 4, 5, 2));
            break;
        case S6IconHeart:
            S6Stroke(S6Heart(), 2);
            break;
        case S6IconHeartFilled:
            [S6Heart() fill];
            break;
        case S6IconAlbum:
            S6Stroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, 18, 18)], 2);
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(9.5, 9.5, 5, 5)] fill];
            break;
        case S6IconArtist:
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(7.5, 2.5, 9, 9)] fill];
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(3, 22)];
            [p addCurveToPoint:CGPointMake(21, 22) controlPoint1:CGPointMake(3, 11) controlPoint2:CGPointMake(21, 11)];
            [p closePath];
            [p fill];
            break;
        case S6IconPodcast:
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(8.5, 2.5, 7, 11) cornerRadius:3.5] fill];
            S6Stroke([UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 10) radius:6.5 startAngle:0 endAngle:M_PI clockwise:YES], 2);
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(12, 16.5)];
            [p addLineToPoint:CGPointMake(12, 21)];
            [p moveToPoint:CGPointMake(8, 21)];
            [p addLineToPoint:CGPointMake(16, 21)];
            S6Stroke(p, 2);
            break;
        case S6IconPlay:
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(6.5, 3.5)];
            [p addLineToPoint:CGPointMake(20.5, 12)];
            [p addLineToPoint:CGPointMake(6.5, 20.5)];
            [p closePath];
            [p fill];
            break;
        case S6IconPause:
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(5, 3.5, 5, 17) cornerRadius:1] fill];
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(14, 3.5, 5, 17) cornerRadius:1] fill];
            break;
        case S6IconNext:
        case S6IconPrevious: {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGContextSaveGState(ctx);
            if (icon == S6IconPrevious) { CGContextTranslateCTM(ctx, 24, 0); CGContextScaleCTM(ctx, -1, 1); }
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(4, 4)];
            [p addLineToPoint:CGPointMake(16, 12)];
            [p addLineToPoint:CGPointMake(4, 20)];
            [p closePath];
            [p fill];
            UIRectFill(CGRectMake(16.5, 4, 3, 16));
            CGContextRestoreGState(ctx);
            break;
        }
        case S6IconShuffle:
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(2.5, 7)];
            [p addLineToPoint:CGPointMake(7, 7)];
            [p addCurveToPoint:CGPointMake(17.5, 17) controlPoint1:CGPointMake(12, 7) controlPoint2:CGPointMake(12, 17)];
            [p addLineToPoint:CGPointMake(19, 17)];
            [p moveToPoint:CGPointMake(2.5, 17)];
            [p addLineToPoint:CGPointMake(7, 17)];
            [p addCurveToPoint:CGPointMake(17.5, 7) controlPoint1:CGPointMake(12, 17) controlPoint2:CGPointMake(12, 7)];
            [p addLineToPoint:CGPointMake(19, 7)];
            S6Stroke(p, 2);
            S6Arrowhead(CGPointMake(22.5, 7), 0, 5);
            S6Arrowhead(CGPointMake(22.5, 17), 0, 5);
            break;
        case S6IconRepeat:
        case S6IconRepeatOne:
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(16, 6.5)];
            [p addLineToPoint:CGPointMake(7, 6.5)];
            [p addCurveToPoint:CGPointMake(3, 10.5) controlPoint1:CGPointMake(4.5, 6.5) controlPoint2:CGPointMake(3, 8)];
            [p addLineToPoint:CGPointMake(3, 13)];
            [p moveToPoint:CGPointMake(8, 17.5)];
            [p addLineToPoint:CGPointMake(17, 17.5)];
            [p addCurveToPoint:CGPointMake(21, 13.5) controlPoint1:CGPointMake(19.5, 17.5) controlPoint2:CGPointMake(21, 16)];
            [p addLineToPoint:CGPointMake(21, 11)];
            S6Stroke(p, 2);
            S6Arrowhead(CGPointMake(20, 6.5), 0, 5);
            S6Arrowhead(CGPointMake(4, 17.5), M_PI, 5);
            if (icon == S6IconRepeatOne) {
                UIFont *f = [UIFont boldSystemFontOfSize:8];
                [@"1" drawAtPoint:CGPointMake(10, 7.8) withFont:f];
            }
            break;
        case S6IconQueue:
            UIRectFill(CGRectMake(3, 5, 12, 2));
            UIRectFill(CGRectMake(3, 10, 12, 2));
            UIRectFill(CGRectMake(3, 15, 12, 2));
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(17, 12)];
            [p addLineToPoint:CGPointMake(22, 15.5)];
            [p addLineToPoint:CGPointMake(17, 19)];
            [p closePath];
            [p fill];
            break;
        case S6IconLyrics:
            p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2.5, 3.5, 19, 14) cornerRadius:3];
            S6Stroke(p, 2);
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(7, 17.5)];
            [p addLineToPoint:CGPointMake(6, 22)];
            [p addLineToPoint:CGPointMake(11.5, 17.5)];
            [p fill];
            UIRectFill(CGRectMake(6.5, 8, 11, 1.8));
            UIRectFill(CGRectMake(6.5, 11.6, 7, 1.8));
            break;
        case S6IconDevices:
            S6Stroke([UIBezierPath bezierPathWithRoundedRect:CGRectMake(6, 2.5, 12, 19) cornerRadius:2], 2);
            S6Stroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(8.5, 11, 7, 7)], 1.8);
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10.8, 5.3, 2.4, 2.4)] fill];
            break;
        case S6IconMore:
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(2.5, 10, 4, 4)] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(10, 10, 4, 4)] fill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(17.5, 10, 4, 4)] fill];
            break;
        case S6IconPlus:
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(12, 4)];
            [p addLineToPoint:CGPointMake(12, 20)];
            [p moveToPoint:CGPointMake(4, 12)];
            [p addLineToPoint:CGPointMake(20, 12)];
            S6Stroke(p, 2.4);
            break;
        case S6IconClose:
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(5, 5)];
            [p addLineToPoint:CGPointMake(19, 19)];
            [p moveToPoint:CGPointMake(19, 5)];
            [p addLineToPoint:CGPointMake(5, 19)];
            S6Stroke(p, 2.4);
            break;
        case S6IconChevronDown:
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(4, 8.5)];
            [p addLineToPoint:CGPointMake(12, 16)];
            [p addLineToPoint:CGPointMake(20, 8.5)];
            S6Stroke(p, 2.6);
            break;
        case S6IconSpeaker:
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(3, 9)];
            [p addLineToPoint:CGPointMake(7, 9)];
            [p addLineToPoint:CGPointMake(12, 4.5)];
            [p addLineToPoint:CGPointMake(12, 19.5)];
            [p addLineToPoint:CGPointMake(7, 15)];
            [p addLineToPoint:CGPointMake(3, 15)];
            [p closePath];
            [p fill];
            S6Stroke([UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 12) radius:4.5 startAngle:-0.9 endAngle:0.9 clockwise:YES], 1.8);
            S6Stroke([UIBezierPath bezierPathWithArcCenter:CGPointMake(12, 12) radius:8.5 startAngle:-0.9 endAngle:0.9 clockwise:YES], 1.8);
            break;
        case S6IconClock:
            S6Stroke([UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, 18, 18)], 2);
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(12, 7)];
            [p addLineToPoint:CGPointMake(12, 12)];
            [p addLineToPoint:CGPointMake(15.5, 14)];
            S6Stroke(p, 2);
            break;
        case S6IconCheck:
            p = [UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(4, 12.5)];
            [p addLineToPoint:CGPointMake(9.5, 18)];
            [p addLineToPoint:CGPointMake(20, 6)];
            S6Stroke(p, 2.6);
            break;
        case S6IconMoon: {
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, 18, 18)] fill];
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGContextSetBlendMode(ctx, kCGBlendModeClear);
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(9, 0.5, 15, 15)] fill];
            CGContextSetBlendMode(ctx, kCGBlendModeNormal);
            break;
        }
    }
}

- (UIImage *)icon:(S6Icon)icon size:(CGFloat)size color:(UIColor *)color
{
    CGFloat r = 0, g = 0, b = 0, a = 1, w = 0;
    BOOL got = NO;
    if ([color respondsToSelector:@selector(getRed:green:blue:alpha:)])
        got = ((BOOL(*)(id,SEL,CGFloat*,CGFloat*,CGFloat*,CGFloat*))objc_msgSend)(color, @selector(getRed:green:blue:alpha:), &r, &g, &b, &a);
    if (!got) {
        CGFloat w = 1;
        if ([color respondsToSelector:@selector(getWhite:alpha:)] && ((BOOL(*)(id,SEL,CGFloat*,CGFloat*))objc_msgSend)(color, @selector(getWhite:alpha:), &w, &a)) { r=g=b=w; got=YES; }
    }
    if (!got) { CGColorRef cg = color.CGColor; if (cg) { size_t n=CGColorGetNumberOfComponents(cg); const CGFloat *c=CGColorGetComponents(cg); if(n>=3){r=c[0];g=c[1];b=c[2];a=c[n-1];} else if(n>=2){r=g=b=c[0];a=c[1];} } }
    NSString *key = [NSString stringWithFormat:@"i%ld-%.1f-%.3f-%.3f-%.3f-%.3f", (long)icon, size, r, g, b, a];
    return [self cached:key build:^id {
        return S6DrawImage(CGSizeMake(size, size), NO, ^(CGContextRef ctx) {
            CGContextScaleCTM(ctx, size / 24.0, size / 24.0);
            [color setFill];
            [color setStroke];
            [self drawIcon:icon];
        });
    }];
}

- (UIImage *)icon:(S6Icon)icon size:(CGFloat)size { return [self icon:icon size:size color:[UIColor whiteColor]]; }

#pragma mark - Fonts

- (UIFont *)titleFont { return [UIFont fontWithName:@"HelveticaNeue-Bold" size:16] ?: [UIFont boldSystemFontOfSize:16]; }
- (UIFont *)bodyFont { return [UIFont fontWithName:@"HelveticaNeue" size:15] ?: [UIFont systemFontOfSize:15]; }
- (UIFont *)boldBodyFont { return [UIFont fontWithName:@"HelveticaNeue-Bold" size:15] ?: [UIFont boldSystemFontOfSize:15]; }
- (UIFont *)smallFont { return [UIFont fontWithName:@"HelveticaNeue" size:12.5] ?: [UIFont systemFontOfSize:12.5]; }
- (UIFont *)headerFont { return [UIFont fontWithName:@"HelveticaNeue-Bold" size:S6IsPad() ? 30 : 22] ?: [UIFont boldSystemFontOfSize:26]; }
- (UIFont *)sectionFont { return [UIFont fontWithName:@"HelveticaNeue-Bold" size:12] ?: [UIFont boldSystemFontOfSize:12]; }

#pragma mark - Applying

- (void)applyGlobalAppearance
{
    UINavigationBar *nav = [UINavigationBar appearance];
    [nav setBackgroundImage:[self navigationBarImage] forBarMetrics:UIBarMetricsDefault];
    if ([nav respondsToSelector:@selector(setTitleTextAttributes:)]) {
        [nav setTitleTextAttributes:@{ UITextAttributeTextColor: [self primaryTextColor],
                                       UITextAttributeTextShadowColor: [UIColor colorWithWhite:0 alpha:0.8],
                                       UITextAttributeTextShadowOffset: [NSValue valueWithUIOffset:UIOffsetMake(0, -1)],
                                       UITextAttributeFont: [self titleFont] }];
    }
    UIBarButtonItem *item = [UIBarButtonItem appearance];
    [item setBackgroundImage:[self darkButtonImageHighlighted:NO] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [item setBackgroundImage:[self darkButtonImageHighlighted:YES] forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    if ([item respondsToSelector:@selector(setTitleTextAttributes:forState:)]) {
        [item setTitleTextAttributes:@{ UITextAttributeTextColor: [self primaryTextColor],
                                        UITextAttributeTextShadowColor: [UIColor colorWithWhite:0 alpha:0.6],
                                        UITextAttributeTextShadowOffset: [NSValue valueWithUIOffset:UIOffsetMake(0, -1)],
                                        UITextAttributeFont: [UIFont boldSystemFontOfSize:12] } forState:UIControlStateNormal];
    }
    [[UITabBar appearance] setBackgroundImage:[self tabBarImage]];
    [[UITabBar appearance] setSelectedImageTintColor:[self accentColor]];
    [[UITabBar appearance] setSelectionIndicatorImage:[[UIImage alloc] init]];
    [[UISlider appearance] setMinimumTrackImage:[self sliderTrackImageFilled:YES] forState:UIControlStateNormal];
    [[UISlider appearance] setMaximumTrackImage:[self sliderTrackImageFilled:NO] forState:UIControlStateNormal];
    [[UISlider appearance] setThumbImage:[self sliderThumbImage] forState:UIControlStateNormal];
    [[UISwitch appearance] setOnTintColor:[self accentColor]];

    // iOS 7 and newer: the same artwork through the appearance objects iOS 13-15 insist on (no-ops on iOS 6)
    S6ModernApplyNavigationBarBackground(nav, [self navigationBarImage], [self modernTitleAttributesSize:0],
                                         [self darkButtonImageHighlighted:NO], [self darkButtonImageHighlighted:YES], [self modernTitleAttributesSize:12]);
    S6ModernApplyTabBarBackground([UITabBar appearance], [self tabBarImage]);
    if (S6ModernIOS()) {
        [[UITabBar appearance] setTintColor:[self accentColor]];       // (the selected tab's colour from iOS 7 on)
        [[UINavigationBar appearance] setTintColor:[self primaryTextColor]];
        [nav setBarStyle:UIBarStyleBlack];
    }
}

// The title attributes with the keys of iOS 7 and newer (0: the bar's title font)
- (NSDictionary *)modernTitleAttributesSize:(CGFloat)size
{
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
    shadow.shadowOffset = CGSizeMake(0, -1);
    return @{ NSForegroundColorAttributeName: [self primaryTextColor],
              NSFontAttributeName: size > 0 ? [UIFont boldSystemFontOfSize:size] : [self titleFont],
              NSShadowAttributeName: shadow };
}

- (void)applyToNavigationBar:(UINavigationBar *)bar
{
    [bar setBackgroundImage:[self navigationBarImage] forBarMetrics:UIBarMetricsDefault];
    bar.barStyle = UIBarStyleBlack;
    S6ModernApplyNavigationBarBackground(bar, [self navigationBarImage], [self modernTitleAttributesSize:0],
                                         [self darkButtonImageHighlighted:NO], [self darkButtonImageHighlighted:YES], [self modernTitleAttributesSize:12]);
}

- (void)applyToTableView:(UITableView *)tableView
{
    tableView.backgroundColor = [self backgroundColor];
    tableView.backgroundView = nil;
    tableView.separatorColor = [self separatorColor];
    tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
}

- (void)styleCell:(UITableViewCell *)cell
{
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [self primaryTextColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.textColor = [self secondaryTextColor];
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    UIView *selected = [[UIView alloc] init];
    selected.backgroundColor = [self rowHighlightColor];
    cell.selectedBackgroundView = selected;
}

- (void)applyToSearchBar:(UISearchBar *)bar
{
    bar.backgroundImage = [self navigationBarImage];
    [bar setSearchFieldBackgroundImage:[self searchFieldImage] forState:UIControlStateNormal];
    UITextField *f = S6ModernSearchBarTextField(bar);   // (nested deeper from iOS 7 on)
    if (f) {
        f.textColor = [self primaryTextColor];
        f.keyboardAppearance = UIKeyboardAppearanceAlert;
    }
}

- (UIButton *)greenButtonWithTitle:(NSString *)title
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setBackgroundImage:[self greenButtonImageHighlighted:NO] forState:UIControlStateNormal];
    [b setBackgroundImage:[self greenButtonImageHighlighted:YES] forState:UIControlStateHighlighted];
    [b setTitle:[title uppercaseString] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:13] ?: [UIFont boldSystemFontOfSize:13];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.35] forState:UIControlStateNormal];
    b.titleLabel.shadowOffset = CGSizeMake(0, -1);
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 22, 0, 22);
    return b;
}

- (UIButton *)outlineButtonWithTitle:(NSString *)title
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setBackgroundImage:[self outlineButtonImageHighlighted:NO] forState:UIControlStateNormal];
    [b setBackgroundImage:[self outlineButtonImageHighlighted:YES] forState:UIControlStateHighlighted];
    [b setTitle:[title uppercaseString] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:12] ?: [UIFont boldSystemFontOfSize:12];
    [b setTitleColor:[self primaryTextColor] forState:UIControlStateNormal];
    b.contentEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 18);
    return b;
}

- (CGFloat)widthForButton:(UIButton *)button minimum:(CGFloat)minimum
{
    CGSize s = [button.currentTitle ?: @"" sizeWithFont:button.titleLabel.font];
    return MAX(minimum, ceilf(s.width) + button.contentEdgeInsets.left + button.contentEdgeInsets.right + 6);
}

- (UIActivityIndicatorViewStyle)spinnerStyle { return UIActivityIndicatorViewStyleWhite; }

@end
