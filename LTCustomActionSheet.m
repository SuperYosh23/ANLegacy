#import "LTCustomActionSheet.h"
#import "LTTransitionSettings.h"
#import "LTLog.h"

@interface LTCustomActionSheet ()
@property (nonatomic, copy) NSString *titleString;
@property (nonatomic, strong) NSArray *buttonTitles;
@property (nonatomic, assign) NSInteger destructiveIndex;
@property (nonatomic, strong) UIView *backgroundView;
@end

@implementation LTCustomActionSheet

- (instancetype)initWithTitle:(NSString *)title buttonTitles:(NSArray *)buttonTitles destructiveIndex:(NSInteger)destructiveIndex {
    self = [super init];
    if (self) {
        _titleString = title;
        _buttonTitles = buttonTitles;
        _destructiveIndex = destructiveIndex;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;

        CGFloat sheetW = 280.0f;
        CGFloat pad = 12.0f;
        CGFloat top = pad;

        // Title
        UILabel *titleLabel = nil;
        if (title.length) {
            titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, top, sheetW - pad * 2, 20)];
            titleLabel.text = title;
            titleLabel.font = [UIFont boldSystemFontOfSize:15];
            titleLabel.textColor = [UIColor whiteColor];
            titleLabel.textAlignment = NSTextAlignmentCenter;
            [self addSubview:titleLabel];
            top += 22.0f + 6.0f;
        }

        // Buttons
        CGFloat buttonHeight = 44.0f;
        CGFloat buttonGap = 1.0f;
        NSInteger count = (NSInteger)buttonTitles.count;
        for (NSInteger i = 0; i < count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = CGRectMake(0, top + i * (buttonHeight + buttonGap), sheetW, buttonHeight);
            [button setTitle:[buttonTitles objectAtIndex:(NSUInteger)i] forState:UIControlStateNormal];
            button.titleLabel.font = [UIFont systemFontOfSize:17];
            if (i == destructiveIndex) {
                [button setTitleColor:[UIColor colorWithRed:1.0f green:0.35f blue:0.35f alpha:1.0f] forState:UIControlStateNormal];
            } else {
                [button setTitleColor:[UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f] forState:UIControlStateNormal];
            }
            button.backgroundColor = [UIColor colorWithRed:0.20f green:0.20f blue:0.20f alpha:1.0f];
            button.tag = i;
            [button addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button];
        }

        CGFloat bottom = top + count * (buttonHeight + buttonGap);
        CGRect sheet = CGRectMake(0, 0, sheetW, bottom + pad);
        self.frame = sheet;
        self.backgroundColor = [UIColor colorWithRed:0.25f green:0.25f blue:0.25f alpha:1.0f];
        self.layer.cornerRadius = 12.0f;
        self.clipsToBounds = YES;
    }
    return self;
}

- (void)buttonTapped:(UIButton *)button {
    [self dismiss];
    if ([self.delegate respondsToSelector:@selector(customActionSheet:tappedButtonAtIndex:)]) {
        [self.delegate customActionSheet:self tappedButtonAtIndex:button.tag];
    }
}

- (void)show {
    UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
    if (!window) window = [[UIApplication sharedApplication] keyWindow];

    self.backgroundView = [[UIView alloc] initWithFrame:window.bounds];
    self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundView.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.5f];

    self.center = CGPointMake(window.bounds.size.width / 2.0f, window.bounds.size.height / 2.0f);
    self.alpha = 0.0f;

    [window addSubview:self.backgroundView];
    [window addSubview:self];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    [self.backgroundView addGestureRecognizer:tap];

    [UIView animateWithDuration:[LTTransitionSettings durationFor:0.2f] animations:^{
        self.alpha = 1.0f;
    }];
}

- (void)dismiss {
    [UIView animateWithDuration:[LTTransitionSettings durationFor:0.2f] animations:^{
        self.alpha = 0.0f;
    } completion:^(BOOL finished) {
        [self.backgroundView removeFromSuperview];
        [self removeFromSuperview];
    }];
}

@end
