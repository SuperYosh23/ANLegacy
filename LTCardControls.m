#import "LTCardControls.h"
#import "LTTheme.h"
#import "LTLog.h"

// The switch of the modern themes.
//
// It draws itself and handles its own touches, so that nothing of the
// platform's switch is underneath to interfere. See the header for why.
@implementation LTCardSwitch {
    BOOL _on;
}

// The property comes from the protocol, so it is synthesised explicitly.
@synthesize on = _on;

- (id)initWithFrame:(CGRect)frame {
    self = (self = [super initWithFrame:frame]) ? self : nil;
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        _on = NO;
        // A control used as a cell's accessory view is laid out from its frame,
        // and a zero-sized one is simply not drawn. The platform's switch got
        // this for free; ours has to say so.
        if (CGRectGetWidth(frame) <= 0.0f || CGRectGetHeight(frame) <= 0.0f) {
            self.frame = CGRectMake(0.0f, 0.0f, 51.0f, 31.0f);
        }
    }
    return self;
}

- (void)setOn:(BOOL)on {
    if (_on == on) return;
    _on = on;
    [self setNeedsDisplay];
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(51.0f, 31.0f);
}

- (void)drawRect:(CGRect)rect {
    CGFloat w = CGRectGetWidth(rect);
    CGFloat h = CGRectGetHeight(rect);
    if (w <= 0.0f || h <= 0.0f) return;
    CGFloat radius = h / 2.0f;
    CGFloat inset = 2.0f;

    CGRect track = CGRectInset(rect, inset, inset);
    UIBezierPath *trackPath = [UIBezierPath bezierPathWithRoundedRect:track cornerRadius:radius];
    if (self.on) {
        [[LTTheme accent] setFill];
    } else {
        [[LTTheme fill] setFill];
    }
    [trackPath fill];

    // The thumb: a filled circle on the off side, and on the on side a filled
    // circle with a check mark in the accent colour, which is Material 3's
    // switch.
    CGFloat thumbDiameter = h - inset * 2.0f - 2.0f;
    CGFloat thumbX = self.on ? (w - inset - thumbDiameter) : inset;
    CGRect thumb = CGRectMake(thumbX, inset + 1.0f, thumbDiameter, thumbDiameter);

    UIBezierPath *thumbPath = [UIBezierPath bezierPathWithOvalInRect:thumb];
    if (self.on) {
        [[UIColor colorWithWhite:1.0f alpha:1.0f] setFill];
        [thumbPath fill];

        UIBezierPath *tick = [UIBezierPath bezierPath];
        CGFloat cx = CGRectGetMidX(thumb);
        CGFloat cy = CGRectGetMidY(thumb);
        CGFloat s = thumbDiameter * 0.24f;
        [tick moveToPoint:CGPointMake(cx - s, cy)];
        [tick addLineToPoint:CGPointMake(cx - s * 0.25f, cy + s * 0.7f)];
        [tick addLineToPoint:CGPointMake(cx + s, cy - s * 0.75f)];
        tick.lineWidth = MAX(1.5f, thumbDiameter * 0.11f);
        tick.lineCapStyle = kCGLineCapRound;
        tick.lineJoinStyle = kCGLineJoinRound;
        [[LTTheme accent] setStroke];
        [tick stroke];
    } else {
        [[LTTheme placeholder] setFill];
        [thumbPath fill];
    }
}

// The tap handling is ours, because there is no platform switch underneath to
// do it for us.
//
// The control is a UIControl, so the touch arrives as touchesBegan: and
// touchesEnded:. The themed table puts the control inside the row it draws, so
// the row hands the touch straight to it.
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];

    // The touch has to have stayed on the control for it to count, which is
    // what UIControl's own tracking works out for us.
    UITouch *touch = [touches anyObject];
    if (!touch) return;
    CGPoint point = [touch locationInView:self];
    if (![self pointInside:point withEvent:event]) return;

    self.on = !self.on;
    LTLog(@"SWITCH tapped on=%d", self.on);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self setNeedsDisplay];
}

@end

@implementation LTCardSegmented {
    UIFont *_titleFont;
}

- (id)initWithFrame:(CGRect)frame {
    self = (self = [super initWithFrame:frame]) ? self : nil;
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        _selectedIndex = 0;
    }
    return self;
}

- (instancetype)initWithItems:(NSArray *)items {
    self = (self = [super initWithFrame:CGRectZero]) ? self : nil;
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        _selectedIndex = 0;
        _items = [items copy];
    }
    return self;
}

- (void)setItems:(NSArray *)items {
    _items = [items copy];
    [self setNeedsDisplay];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (_selectedIndex == selectedIndex) return;
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay];
}

- (NSInteger)numberOfSegments {
    return (NSInteger)self.items.count;
}

- (void)setTitleTextAttributes:(NSDictionary *)attributes forState:(UIControlState)state {
    // Callers built against the older SDK pass the font under the pre-iOS-7
    // attribute key. Find it by value so either spelling works, and so this
    // class never has to read a newer weak-imported string constant.
    UIFont *font = nil;
    for (id value in [attributes objectEnumerator]) {
        if ([value isKindOfClass:[UIFont class]]) {
            font = value;
            break;
        }
    }
    if (font) {
        _titleFont = font;
        [self setNeedsDisplay];
    }
}

- (CGFloat)itemWidth {
    NSInteger count = [self numberOfSegments];
    if (count <= 0) return 0.0f;
    return CGRectGetWidth(self.bounds) / (CGFloat)count;
}

- (void)drawRect:(CGRect)rect {
    CGFloat radius = CGRectGetHeight(rect) / 2.0f;
    if (radius <= 0.0f) return;

    UIBezierPath *track = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:radius];
    [[LTTheme fill] setFill];
    [track fill];

    CGFloat width = [self itemWidth];
    if (width > 0.0f && self.selectedIndex < [self numberOfSegments]) {
        CGRect pill = CGRectMake(self.selectedIndex * width, 0.0f, width, CGRectGetHeight(rect));
        // Inset a little so the pill reads as sitting inside the track.
        pill = CGRectInset(pill, 3.0f, 3.0f);
        UIBezierPath *pillPath = [UIBezierPath bezierPathWithRoundedRect:pill
                                                          cornerRadius:CGRectGetHeight(pill) / 2.0f];
        [[LTTheme cellBackground] setFill];
        [pillPath fill];
    }

    UIFont *font = _titleFont ?: [UIFont systemFontOfSize:13.0f];
    CGFloat itemHeight = CGRectGetHeight(rect);
    for (NSInteger i = 0; i < [self numberOfSegments]; i++) {
        NSString *title = [self.items objectAtIndex:(NSUInteger)i];
        if (![title isKindOfClass:[NSString class]]) continue;
        CGRect item = CGRectMake(i * width, 0.0f, width, itemHeight);
        CGSize size = [title sizeWithFont:font];
        // Keep the label strictly inside its segment and the control. A long
        // title in a short control would otherwise be drawn over its neighbours
        // and past the rounded track, which reads as the text "falling out".
        size.width = MIN(size.width, MAX(1.0f, width - 8.0f));
        size.height = MIN(size.height, MAX(1.0f, itemHeight - 2.0f));
        CGRect label = CGRectMake(CGRectGetMinX(item) + (width - size.width) / 2.0f,
                                  CGRectGetMidY(item) - size.height / 2.0f,
                                  size.width, size.height);
        if (i == self.selectedIndex) {
            [[LTTheme text] setFill];
        } else {
            [[LTTheme secondaryText] setFill];
        }
        [title drawInRect:label withFont:font];
    }
}

// Each segment is a touch target of its own, so the tap is turned into a
// selection and reported the way the platform's segmented control reports it.
- (void)touchUpInside:(id)sender {
    NSInteger index = [sender tag];
    if (index < 0 || index >= [self numberOfSegments]) return;
    if (index == self.selectedIndex) return;
    self.selectedIndex = index;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

// The touch lands on the control, not on a per-segment button, so the segment
// is worked out from where the touch was. The control has no subviews to
// interfere with, which is the whole point of drawing it ourselves.
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    UITouch *touch = [touches anyObject];
    if (!touch) return;
    CGFloat width = [self itemWidth];
    if (width <= 0.0f) return;
    CGPoint point = [touch locationInView:self];
    NSInteger index = (NSInteger)floor(point.x / width);
    if (index < 0 || index >= [self numberOfSegments]) return;
    if (index == self.selectedIndex) return;
    self.selectedIndex = index;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

// Reports which segment was tapped, the way -valueChanged does for the
// platform's control.
- (NSInteger)selectedSegmentIndex {
    return self.selectedIndex;
}

// The screens set the selection through the platform's spelling, so this needs
// to exist or the call goes nowhere.
- (void)setSelectedSegmentIndex:(NSInteger)index {
    self.selectedIndex = index;
}

@end

@implementation LTCompactSegmentedControl {
    UIFont *_compactFont;
}

- (void)setCompactTitleFont:(UIFont *)font {
    if (_compactFont == font) return;
    _compactFont = font;
    [self applyCompactFont];
}

- (void)lt_applyFont:(UIFont *)font toLabelTree:(UIView *)view {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UILabel class]]) {
            ((UILabel *)sub).font = font;
        }
        [self lt_applyFont:font toLabelTree:sub];
    }
}

- (void)applyCompactFont {
    if (!_compactFont) return;
    [self lt_applyFont:_compactFont toLabelTree:self];
    [self setNeedsDisplay];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self applyCompactFont];
}

@end

@implementation LTSectionHeaderView

+ (instancetype)headerWithTitle:(NSString *)title {
    LTSectionHeaderView *view = [[LTSectionHeaderView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = [UIColor clearColor];
    view.opaque = NO;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:13.0f];
    label.textColor = [LTTheme secondaryText];
    label.backgroundColor = [UIColor clearColor];
    [view addSubview:label];
    return view;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    for (UIView *subview in self.subviews) {
        if (![subview isKindOfClass:[UILabel class]]) continue;
        CGRect frame = subview.frame;
        frame.origin.x = 16.0f;
        frame.origin.y = 0.0f;
        frame.size.width = CGRectGetWidth(self.bounds) - 16.0f;
        frame.size.height = CGRectGetHeight(self.bounds);
        subview.frame = frame;
    }
}

@end
