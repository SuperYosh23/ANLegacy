#import "S6LoginViewController.h"
#import "S6Session.h"
#import "S6Zeroconf.h"
#import "S6Settings.h"
#import "S6Theme.h"
#import "S6Modern.h"
#import "S6Common.h"

@interface S6LoginViewController ()
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIImageView *mark;
@property (nonatomic, strong) UILabel *appName;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSArray *stepNumbers;
@property (nonatomic, strong) NSArray *stepLabels;
@property (nonatomic, strong) UIView *statusBox;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UILabel *noteLabel;
@end

@implementation S6LoginViewController

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (UILabel *)label:(UIFont *)font color:(UIColor *)color in:(UIView *)parent
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.font = font;
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    l.numberOfLines = 0;
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
    l.shadowOffset = CGSizeMake(0, -1);
    [parent addSubview:l];
    return l;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    S6Theme *theme = [S6Theme shared];
    self.view.backgroundColor = [theme backgroundColor];
    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.scroll.alwaysBounceVertical = YES;
    [self.view addSubview:self.scroll];

    self.mark = [[UIImageView alloc] initWithImage:[theme brandMarkWithSize:S6IsPad() ? 96 : 72]];
    [self.scroll addSubview:self.mark];
    self.appName = [self label:[UIFont fontWithName:@"HelveticaNeue-Bold" size:S6IsPad() ? 40 : 30] ?: [UIFont boldSystemFontOfSize:34]
                         color:[UIColor whiteColor] in:self.scroll];
    self.appName.text = @"Sixify";
    self.appName.textAlignment = NSTextAlignmentCenter;
    self.titleLabel = [self label:[UIFont fontWithName:@"HelveticaNeue-Bold" size:S6IsPad() ? 22 : 18] ?: [UIFont boldSystemFontOfSize:20]
                            color:[theme primaryTextColor] in:self.scroll];
    self.titleLabel.text = L(@"Log in with the Spotify app on your phone");
    self.titleLabel.textAlignment = NSTextAlignmentCenter;

    NSString *device = S6IsPad() ? L(@"iPad") : L(@"iPhone");
    NSArray *steps = @[ [NSString stringWithFormat:L(@"Connect this %@ and your phone to the same Wi-Fi."), device],
                        L(@"Open Spotify on your phone and start playing anything."),
                        [NSString stringWithFormat:L(@"Tap the devices button and choose “%@”."), [S6Settings deviceName]],
                        L(@"Sixify logs in by itself. Then you control everything right here.") ];
    NSMutableArray *numbers = [NSMutableArray array], *labels = [NSMutableArray array];
    for (NSUInteger i = 0; i < steps.count; i++) {
        UILabel *n = [self label:[UIFont fontWithName:@"HelveticaNeue-Bold" size:15] ?: [UIFont boldSystemFontOfSize:15] color:[UIColor whiteColor] in:self.scroll];
        n.text = [NSString stringWithFormat:@"%lu", (unsigned long)i + 1];
        n.textAlignment = NSTextAlignmentCenter;
        n.backgroundColor = [theme accentColor];
        n.layer.cornerRadius = 13;
        n.clipsToBounds = YES;
        n.shadowColor = nil;
        [numbers addObject:n];
        UILabel *l = [self label:[UIFont fontWithName:@"HelveticaNeue" size:S6IsPad() ? 17 : 15] ?: [UIFont systemFontOfSize:16]
                           color:[theme primaryTextColor] in:self.scroll];
        l.text = steps[i];
        [labels addObject:l];
    }
    self.stepNumbers = numbers;
    self.stepLabels = labels;

    self.statusBox = [[UIView alloc] initWithFrame:CGRectZero];
    self.statusBox.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.statusBox.layer.cornerRadius = 10;
    self.statusBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;
    self.statusBox.layer.borderWidth = 1;
    [self.scroll addSubview:self.statusBox];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.hidesWhenStopped = YES;
    [self.statusBox addSubview:self.spinner];
    self.statusLabel = [self label:[theme boldBodyFont] color:[theme primaryTextColor] in:self.statusBox];
    self.retryButton = [theme greenButtonWithTitle:L(@"Try again")];
    [self.retryButton addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.retryButton];

    self.noteLabel = [self label:[theme smallFont] color:[theme secondaryTextColor] in:self.scroll];
    self.noteLabel.textAlignment = NSTextAlignmentCenter;
    self.noteLabel.text = L(@"Sixify needs Spotify Premium. Your password never goes through this app: the Spotify app hands over a login meant only for this device. Sixify is not made by Spotify.");

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(update) name:S6ZeroconfDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(update) name:S6SessionStateDidChangeNotification object:nil];
    if (![S6Zeroconf shared].running) [[S6Zeroconf shared] start];
    [self update];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGSize s = self.view.bounds.size;
    CGFloat w = MIN(s.width - 40, 520), x = (s.width - w) / 2;
    CGFloat y = (S6IsPad() ? MAX(40, (s.height - 640) / 2) : 30) + S6SafeAreaInsets(self.view).top;   // (the notch on iOS 11+)
    CGFloat markSide = self.mark.image.size.width;
    self.mark.frame = CGRectMake((s.width - markSide) / 2, y, markSide, markSide);
    y += markSide + 8;
    self.appName.frame = CGRectMake(x, y, w, S6IsPad() ? 48 : 36);
    y += self.appName.frame.size.height + 14;
    CGSize t = [self.titleLabel.text sizeWithFont:self.titleLabel.font constrainedToSize:CGSizeMake(w, 200)];
    self.titleLabel.frame = CGRectMake(x, y, w, ceilf(t.height));
    y += ceilf(t.height) + 22;
    for (NSUInteger i = 0; i < self.stepLabels.count; i++) {
        UILabel *l = self.stepLabels[i];
        CGSize ls = [l.text sizeWithFont:l.font constrainedToSize:CGSizeMake(w - 40, 200)];
        ((UILabel *)self.stepNumbers[i]).frame = CGRectMake(x, y, 26, 26);
        l.frame = CGRectMake(x + 40, y + 3, w - 40, MAX(20, ceilf(ls.height)));
        y += MAX(26, ceilf(ls.height) + 3) + 14;
    }
    y += 8;
    CGSize st = [self.statusLabel.text ?: @"" sizeWithFont:self.statusLabel.font constrainedToSize:CGSizeMake(w - 64, 200)];
    CGFloat boxH = MAX(52, ceilf(st.height) + 30);
    self.statusBox.frame = CGRectMake(x, y, w, boxH);
    self.spinner.center = CGPointMake(26, boxH / 2);
    BOOL spinning = self.spinner.isAnimating;
    self.statusLabel.frame = CGRectMake(spinning ? 48 : 18, 15, w - (spinning ? 64 : 34), boxH - 30);
    y += boxH + 14;
    if (!self.retryButton.hidden) {
        self.retryButton.frame = CGRectMake((s.width - 180) / 2, y, 180, 36);
        y += 36 + 14;
    }
    CGSize ns = [self.noteLabel.text sizeWithFont:self.noteLabel.font constrainedToSize:CGSizeMake(w, 300)];
    self.noteLabel.frame = CGRectMake(x, y + 6, w, ceilf(ns.height));
    y += ceilf(ns.height) + 40;
    self.scroll.contentSize = CGSizeMake(s.width, y);
}

- (void)update
{
    S6Session *session = [S6Session shared];
    S6Zeroconf *zc = [S6Zeroconf shared];
    NSString *status;
    BOOL spin = NO, retry = NO, bad = NO;
    if (session.state == S6SessionStateConnecting) {
        status = session.username.length ? [NSString stringWithFormat:L(@"Logging in as %@…"), session.username] : L(@"Logging in…");
        spin = YES;
    } else if (session.state == S6SessionStateFailed) {
        status = [NSString stringWithFormat:L(@"Spotify refused the login: %@ Pick this device in the Spotify app again."),
                  session.lastError.localizedDescription ?: L(@"unknown reason.")];
        bad = YES;
    } else if (!zc.running) {
        status = L(@"This device could not show itself on the Wi-Fi. Check that Wi-Fi is on.");
        retry = YES;
        bad = YES;
    } else {
        status = [NSString stringWithFormat:L(@"Waiting for your phone… (look for “%@”)"), [S6Settings deviceName]];
        spin = YES;
    }
    self.statusLabel.text = status;
    self.statusLabel.textColor = bad ? [UIColor colorWithRed:1 green:0.55 blue:0.5 alpha:1] : [[S6Theme shared] primaryTextColor];
    if (spin) [self.spinner startAnimating]; else [self.spinner stopAnimating];
    self.retryButton.hidden = !retry;
    [self.view setNeedsLayout];
}

- (void)retry
{
    [[S6Zeroconf shared] stop];
    [[S6Zeroconf shared] start];
    [self update];
}

@end
