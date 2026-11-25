#import "LTLyricsOffsetViewController.h"
#import "LTTheme.h"
#import "LTLyricsSettings.h"

// Dark slider screen, matching LTTransitionSpeedViewController.
@interface LTLyricsOffsetViewController ()
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UISlider *slider;
@end

@implementation LTLyricsOffsetViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        [(id)self setValue:[NSNumber numberWithInteger:0] forKey:@"edgesForExtendedLayout"];
    }
    self.title = @"Lyrics Offset";
    self.view.backgroundColor = [LTTheme background];

    CGFloat width = self.view.bounds.size.width;
    CGFloat pad = 20.0f;

    UILabel *desc = [[UILabel alloc] initWithFrame:CGRectMake(pad, 20, width - pad * 2, 56)];
    desc.text = @"If the highlighted line runs ahead of or behind the music, nudge this until they match.";
    desc.font = [UIFont systemFontOfSize:14];
    desc.textColor = [UIColor lightGrayColor];
    desc.backgroundColor = [UIColor clearColor];
    desc.numberOfLines = 0;
    desc.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:desc];

    self.valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, 84, width - pad * 2, 30)];
    self.valueLabel.text = [self formattedOffset:LTLyricsOffset()];
    self.valueLabel.font = [UIFont boldSystemFontOfSize:22];
    self.valueLabel.textColor = [UIColor colorWithRed:0.35f green:0.68f blue:0.88f alpha:1.0f];
    self.valueLabel.backgroundColor = [UIColor clearColor];
    self.valueLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.valueLabel];

    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(pad, 134, width - pad * 2, 30)];
    self.slider.minimumValue = -5.0f;
    self.slider.maximumValue = 5.0f;
    self.slider.value = (float)LTLyricsOffset();
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.slider];

    UILabel *early = [[UILabel alloc] initWithFrame:CGRectMake(pad, 172, (width - pad * 2) / 2, 18)];
    early.text = @"lyrics early";
    early.font = [UIFont systemFontOfSize:12];
    early.textColor = [UIColor whiteColor];
    early.backgroundColor = [UIColor clearColor];
    early.textAlignment = NSTextAlignmentLeft;
    [self.view addSubview:early];

    UILabel *late = [[UILabel alloc] initWithFrame:CGRectMake(width / 2, 172, (width - pad * 2) / 2, 18)];
    late.text = @"lyrics late";
    late.font = [UIFont systemFontOfSize:12];
    late.textColor = [UIColor whiteColor];
    late.backgroundColor = [UIColor clearColor];
    late.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:late];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    reset.frame = CGRectMake(width / 2 - 50, 206, 100, 30);
    [reset setTitle:@"Reset" forState:UIControlStateNormal];
    [reset setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:15];
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:reset];
}

- (NSString *)formattedOffset:(double)seconds {
    if (fabs(seconds) < 0.05) return @"0.0s (synced)";
    return [NSString stringWithFormat:@"%+.1fs", seconds];
}

- (void)sliderChanged:(UISlider *)slider {
    // Snap to 0.1s so the label does not show a jittery value.
    double snapped = round((double)slider.value * 10.0) / 10.0;
    slider.value = (float)snapped;
    LTSetLyricsOffset(snapped);
    self.valueLabel.text = [self formattedOffset:snapped];
}

- (void)resetTapped {
    self.slider.value = 0.0f;
    LTSetLyricsOffset(0.0);
    self.valueLabel.text = [self formattedOffset:0.0];
}

@end