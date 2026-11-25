#import "LTLyricsPaperView.h"
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

// The paper's colours: warm, slightly yellowed, the way old paper is.
static UIColor *LTPaperTopColor(void) {
    return [UIColor colorWithRed:0.984f green:0.969f blue:0.925f alpha:1.0f];
}
static UIColor *LTPaperBottomColor(void) {
    return [UIColor colorWithRed:0.945f green:0.922f blue:0.855f alpha:1.0f];
}
static UIColor *LTPaperEdgeColor(void) {
    return [UIColor colorWithRed:0.549f green:0.510f blue:0.435f alpha:1.0f];
}

static const CGFloat LTPaperCornerRadius = 8.0f;

// The colour's components, as the gradient wants them.
static void LTPaperComponents(UIColor *color, CGFloat *out) {
    CGFloat r = 0.0f, g = 0.0f, b = 0.0f, a = 1.0f;
    BOOL got = NO;
    if ([color respondsToSelector:@selector(getRed:green:blue:alpha:)])
        got = ((BOOL(*)(id,SEL,CGFloat*,CGFloat*,CGFloat*,CGFloat*))objc_msgSend)(color, @selector(getRed:green:blue:alpha:), &r, &g, &b, &a);
    if (!got && [color respondsToSelector:@selector(getWhite:alpha:)]) {
        CGFloat w = 1.0f;
        if (((BOOL(*)(id,SEL,CGFloat*,CGFloat*))objc_msgSend)(color, @selector(getWhite:alpha:), &w, &a)) { r = g = b = w; got = YES; }
    }
    if (!got) {
        CGColorRef cg = color.CGColor;
        if (cg) {
            size_t n = CGColorGetNumberOfComponents(cg);
            const CGFloat *c = CGColorGetComponents(cg);
            if (n >= 3) { r = c[0]; g = c[1]; b = c[2]; a = c[n-1]; }
            else if (n >= 2) { r = g = b = c[0]; a = c[1]; }
        }
    }
    out[0] = r; out[1] = g; out[2] = b; out[3] = a;
}

@implementation LTLyricsPaperView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        // The sheet sits on the dark drawer, so it needs to cast a shadow to
        // look like it is lying on top of it.
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4f;
        self.layer.shadowOffset = CGSizeMake(0.0f, 2.0f);
        self.layer.shadowRadius = 4.0f;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // The shadow follows the sheet's shape rather than its square.
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                                        cornerRadius:LTPaperCornerRadius].CGPath;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    // The hairline sits on the pixel boundary, so the card is inset by half a
    // point to keep it from being drawn twice.
    CGRect card = CGRectInset(self.bounds, 0.5f, 0.5f);
    if (CGRectGetWidth(card) <= 0.0f || CGRectGetHeight(card) <= 0.0f) return;

    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:card
                                                     cornerRadius:LTPaperCornerRadius];

    CGContextSaveGState(ctx);
    [path addClip];

    // The sheet itself, very slightly darker towards the bottom.
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (space) {
        CGFloat comps[8];
        LTPaperComponents(LTPaperTopColor(), comps);
        LTPaperComponents(LTPaperBottomColor(), comps + 4);
        CGFloat locations[2] = {0.0f, 1.0f};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, locations, 2);
        if (gradient) {
            CGContextDrawLinearGradient(ctx, gradient,
                                         CGPointMake(0.0f, CGRectGetMinY(card)),
                                         CGPointMake(0.0f, CGRectGetMaxY(card)), 0);
            CGGradientRelease(gradient);
        }
        CGColorSpaceRelease(space);
    }

    CGContextRestoreGState(ctx);

    // The edge: a hairline, with a light line just inside it. That pairing is
    // what made the old raised rows look raised.
    [[LTPaperEdgeColor() colorWithAlphaComponent:0.55f] setStroke];
    path.lineWidth = 1.0f;
    [path stroke];

    UIBezierPath *inner = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(card, 1.0f, 1.0f)
                                                       cornerRadius:LTPaperCornerRadius - 1.0f];
    [[UIColor colorWithWhite:1.0f alpha:0.7f] setStroke];
    inner.lineWidth = 1.0f;
    [inner stroke];
}

@end
