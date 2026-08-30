#import "LTSpinnerView.h"
#import <QuartzCore/QuartzCore.h>

@implementation LTSpinnerView {
    CAShapeLayer *_ringLayer;
    BOOL _animating;
}

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _lineWidth = 2.0f;
        _hidesWhenStopped = YES;
        self.backgroundColor = [UIColor clearColor];
        _ringLayer = [CAShapeLayer layer];
        _ringLayer.strokeColor = [[UIColor colorWithRed:0.0f green:0.478f blue:1.0f alpha:1.0f] CGColor];
        _ringLayer.fillColor = [UIColor clearColor].CGColor;
        _ringLayer.lineCap = kCALineCapRound;
        _ringLayer.frame = self.bounds;
        [self.layer addSublayer:_ringLayer];
        [self setNeedsLayout];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _ringLayer.frame = self.bounds;
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat size = MIN(w, h);
    if (size <= 0) return;
    CGFloat line = self.lineWidth;
    CGFloat radius = (size - line) / 2.0f;
    CGPoint center = CGPointMake(w / 2.0f, h / 2.0f);
    CGFloat startAngle = -M_PI_2;
    CGFloat sweep = 1.62f * M_PI;
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                        radius:radius
                                                    startAngle:startAngle
                                                      endAngle:startAngle + sweep
                                                     clockwise:YES];
    _ringLayer.lineWidth = line;
    _ringLayer.path = path.CGPath;
}

- (void)startAnimating {
    if (_animating) return;
    _animating = YES;
    self.hidden = NO;
    CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation"];
    rotation.fromValue = @(0);
    rotation.toValue = @(2 * M_PI);
    rotation.duration = 0.85;
    rotation.repeatCount = INFINITY;
    rotation.removedOnCompletion = NO;
    [self.layer addAnimation:rotation forKey:@"LTSpinnerRotation"];
}

- (void)stopAnimating {
    if (!_animating) return;
    _animating = NO;
    [self.layer removeAnimationForKey:@"LTSpinnerRotation"];
    if (self.hidesWhenStopped) self.hidden = YES;
}

- (BOOL)isAnimating {
    return _animating;
}

@end